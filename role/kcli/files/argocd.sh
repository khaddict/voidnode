#!/bin/bash

export ARGOCD_NAMESPACE="argocd"
export VAULT_TOKEN={{ vault_token }}
export VAULT_ADDR="https://vault.homelab.lan:8200/"
export VERSION="8.5.10"

if ! kubectl get namespace $ARGOCD_NAMESPACE &> /dev/null; then
    echo "Creating namespace $ARGOCD_NAMESPACE..."
    kubectl create namespace $ARGOCD_NAMESPACE
else
    echo "Namespace $ARGOCD_NAMESPACE already exists, skipping creation."
fi

kubectl apply -f /root/apps/argocd/argocd_configmap.yaml --namespace $ARGOCD_NAMESPACE

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create secret generic vault-configuration \
    --namespace $ARGOCD_NAMESPACE \
    --from-literal=VAULT_ADDR=$VAULT_ADDR \
    --from-literal=VAULT_TOKEN=$VAULT_TOKEN \
    --from-literal=AVP_AUTH_TYPE=token \
    --from-literal=AVP_TYPE=vault \
    --from-literal=VAULT_CACERT=/ca/homelab.chain.crt

export CA_HOMELAB_SECRET=$(vault kv get -tls-skip-verify -field="homelab.chain.crt" "kv/easypki/root")

kubectl create secret generic ca-homelab-secret \
    --namespace $ARGOCD_NAMESPACE \
    --from-literal=homelab.chain.crt="$CA_HOMELAB_SECRET"

echo "Installing/Upgrading ArgoCD Helm chart to version $VERSION..."
helm upgrade --install argocd argo/argo-cd --namespace $ARGOCD_NAMESPACE --version $VERSION -f /root/apps/argocd/argocd_values.yaml -f /root/apps/argocd/argocd_overrides.yaml --set configs.params."server\.insecure"=true

echo "Waiting for ArgoCD components to initialize..."
sleep 40

export ARGOCD_CERT_SECRET=$(vault kv get -tls-skip-verify -field="argocd.homelab.lan.cert.pem" "kv/easypki/application/argocd.homelab.lan")
export ARGOCD_KEY_SECRET=$(vault kv get -tls-skip-verify -field="argocd.homelab.lan.key.pem" "kv/easypki/application/argocd.homelab.lan")

echo "$ARGOCD_CERT_SECRET" > /tmp/argocd.cert.pem
echo "$ARGOCD_KEY_SECRET" > /tmp/argocd.key.pem

kubectl create secret tls argocd-cert-secret \
    --namespace $ARGOCD_NAMESPACE \
    --cert=/tmp/argocd.cert.pem \
    --key=/tmp/argocd.key.pem

rm /tmp/argocd.cert.pem /tmp/argocd.key.pem

kubectl apply -f /root/apps/argocd/argocd_ingressroute.yaml --namespace $ARGOCD_NAMESPACE

export ARGOCD_SERVER_POD=$(kubectl get pods -n $ARGOCD_NAMESPACE | grep -i "argocd-server" | awk '{print $1}')
export ARGOCD_SERVER=$(kubectl get svc argocd-server -n $ARGOCD_NAMESPACE -o json | jq -r .spec.clusterIP)
export ARGOCD_INITIAL_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
export ARGOCD_PASSWORD=$(vault kv get -tls-skip-verify -field="argocd_dashboard_password" "kv/kubernetes")

if kubectl exec $ARGOCD_SERVER_POD -n $ARGOCD_NAMESPACE -- argocd login $ARGOCD_SERVER:443 --username admin --password $ARGOCD_INITIAL_PASSWORD --skip-test-tls --grpc-web --plaintext --insecure; then
  kubectl exec $ARGOCD_SERVER_POD -n $ARGOCD_NAMESPACE -- argocd account update-password --account admin --current-password $ARGOCD_INITIAL_PASSWORD --new-password $ARGOCD_PASSWORD --server $ARGOCD_SERVER:443
else
  echo "The initial password has already been changed, no action needed."
fi