#!/bin/bash
set -euo pipefail

ARGOCD_NAMESPACE="argocd"
export VAULT_ADDR="https://vault.khaddict.lab:8200/"
VERSION="9.4.10"

APP_OF_APPS_FILE="/root/bootstrap/voidnode-app-of-apps.yaml"
ARGOCD_HTTPROUTE_FILE="/root/bootstrap/argocd-httproute.yaml"
SYSTEM_APP_NAME="system"
SYSTEM_WAIT_TIMEOUT=900
SYSTEM_WAIT_INTERVAL=10

trap 'rm -f /tmp/argocd.cert.pem /tmp/argocd.key.pem' EXIT

if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    echo "Creating namespace $ARGOCD_NAMESPACE..."
    kubectl create namespace "$ARGOCD_NAMESPACE"
else
    echo "Namespace $ARGOCD_NAMESPACE already exists, skipping creation."
fi

kubectl apply -f /root/bootstrap/argocd-configmap.yaml -n "$ARGOCD_NAMESPACE"

helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

kubectl create secret generic vault-configuration \
    --namespace "$ARGOCD_NAMESPACE" \
    --from-literal=VAULT_ADDR="$VAULT_ADDR" \
    --from-literal=VAULT_TOKEN="$VAULT_TOKEN" \
    --from-literal=AVP_AUTH_TYPE=token \
    --from-literal=AVP_TYPE=vault \
    --from-literal=VAULT_CACERT=/ca/voidnode.chain.pem \
    --dry-run=client -o yaml | kubectl apply -f -

CA_VOIDNODE_SECRET=$(vault kv get -tls-skip-verify -field="voidnode.chain.pem" "kv/easypki/chain")

kubectl create secret generic ca-voidnode-secret \
    --namespace "$ARGOCD_NAMESPACE" \
    --from-literal=voidnode.chain.pem="$CA_VOIDNODE_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/Upgrading ArgoCD Helm chart to version $VERSION..."
helm upgrade --install argocd argo/argo-cd \
    --namespace "$ARGOCD_NAMESPACE" \
    --version "$VERSION" \
    -f /root/bootstrap/argocd-values.yaml \
    -f /root/bootstrap/argocd-overrides.yaml \
    --set configs.params."server\.insecure"=true

echo "Waiting for ArgoCD components to initialize..."
kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=180s
kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=180s || true

ARGOCD_CERT_SECRET=$(vault kv get -tls-skip-verify -field="argocd.khaddict.lab.cert.pem" "kv/easypki/server/argocd.khaddict.lab")
ARGOCD_KEY_SECRET=$(vault kv get -tls-skip-verify -field="argocd.khaddict.lab.key.pem" "kv/easypki/server/argocd.khaddict.lab")

printf '%s\n' "$ARGOCD_CERT_SECRET" > /tmp/argocd.cert.pem
printf '%s\n' "$ARGOCD_KEY_SECRET" > /tmp/argocd.key.pem

kubectl create secret tls argocd-cert-secret \
    --namespace "$ARGOCD_NAMESPACE" \
    --cert=/tmp/argocd.cert.pem \
    --key=/tmp/argocd.key.pem \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /root/bootstrap/argocd-rbac.yaml -n "$ARGOCD_NAMESPACE"

ARGOCD_SERVER_POD=$(kubectl get pod -n "$ARGOCD_NAMESPACE" \
  -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].metadata.name}')

ARGOCD_SERVER=$(kubectl get svc argocd-server -n "$ARGOCD_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
ARGOCD_INITIAL_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGOCD_PASSWORD=$(vault kv get -tls-skip-verify -field="argocd_dashboard_password" "kv/kubernetes")

if kubectl exec "$ARGOCD_SERVER_POD" -n "$ARGOCD_NAMESPACE" -- \
  argocd login "$ARGOCD_SERVER:443" \
  --username admin \
  --password "$ARGOCD_INITIAL_PASSWORD" \
  --skip-test-tls \
  --grpc-web \
  --plaintext \
  --insecure; then
  kubectl exec "$ARGOCD_SERVER_POD" -n "$ARGOCD_NAMESPACE" -- \
    argocd account update-password \
    --account admin \
    --current-password "$ARGOCD_INITIAL_PASSWORD" \
    --new-password "$ARGOCD_PASSWORD" \
    --server "$ARGOCD_SERVER:443"
else
  echo "Failed to log in with the initial admin password. It may already have been changed, or Argo CD may not be ready yet."
fi

echo "Applying app of apps..."
kubectl apply -f "$APP_OF_APPS_FILE" -n "$ARGOCD_NAMESPACE"

echo "Waiting for Argo CD application '$SYSTEM_APP_NAME' to become Synced and Healthy..."
end=$((SECONDS + SYSTEM_WAIT_TIMEOUT))

while true; do
  if (( SECONDS >= end )); then
    echo "Timeout while waiting for application '$SYSTEM_APP_NAME'."
    kubectl get application "$SYSTEM_APP_NAME" -n "$ARGOCD_NAMESPACE" -o yaml || true
    exit 1
  fi

  if ! kubectl get application "$SYSTEM_APP_NAME" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    echo "Application '$SYSTEM_APP_NAME' not created yet, waiting..."
    sleep "$SYSTEM_WAIT_INTERVAL"
    continue
  fi

  sync_status="$(kubectl get application "$SYSTEM_APP_NAME" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health_status="$(kubectl get application "$SYSTEM_APP_NAME" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  echo "Application $SYSTEM_APP_NAME => sync=${sync_status:-Unknown}, health=${health_status:-Unknown}"

  if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
    echo "Application '$SYSTEM_APP_NAME' is Synced and Healthy."
    break
  fi

  sleep "$SYSTEM_WAIT_INTERVAL"
done

echo "Applying Argo CD HTTPRoute..."
kubectl apply -f "$ARGOCD_HTTPROUTE_FILE" -n "$ARGOCD_NAMESPACE"
