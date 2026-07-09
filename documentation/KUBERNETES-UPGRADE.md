# Talos & Kubernetes upgrades

Cluster:
- 1 control-plane: `kcontrol.khaddict.lab - 10.40.0.5`
- 2 workers: `kworker01.khaddict.lab - 10.40.0.6` & `kworker02.khaddict.lab - 10.40.0.7`

All commands below run from `kcli.khaddict.lab`, which holds `talosconfig` & `kubeconfig`.

Two independent upgrades:

1. The **Talos OS** running on the nodes (`talosctl upgrade`)
2. The **Kubernetes version** running on top of it (`talosctl upgrade-k8s`).

Bump Talos first if you also need a newer Kubernetes version than your current Talos release supports (see section 2 below).

## Kubernetes version upgrade

### 1. Check current versions

```bash
talosctl version --client
kubectl get nodes -o wide
```

### 2. Make sure talosctl is new enough

`talosctl upgrade-k8s` refuses any Kubernetes version it doesn't know about yet. Its compatibility matrix is baked into the client binary at release time, not fetched dynamically. If the target Kubernetes version was released after your current `talosctl` client, the command fails with `unsupported upgrade path`, even for a plain one-minor-version bump.

`talosctl` on `kcli` is Salt-managed (`role/kcli/init.sls`, version pinned in `data/versions.yaml`, tracked by Renovate). Bump `data/versions.yaml`'s `talosctl` value to the version that shipped support for your target Kubernetes release (check the "Component Updates" section of the relevant [Talos release notes](https://github.com/siderolabs/talos/releases)), then highstate `kcli`:

```bash
salt-call state.highstate
talosctl version --client
```

### 3. Run the upgrade

Kubernetes only supports upgrading one minor version at a time. Don't skip versions.

```bash
talosctl upgrade-k8s --nodes 10.40.0.5 --to <TARGET_VERSION>
```

A single command handles the whole cluster: `kube-apiserver` / `kube-controller-manager` / `kube-scheduler` on the control-plane, then `kubelet` on every node (control-plane and workers), one at a time. Expect repeated `waiting, config version mismatch: got "N", expected "N+1"` lines per component. This is normal polling while a static pod manifest gets regenerated and the new pod becomes ready. Only worth investigating if it doesn't progress for 3-4+ minutes on the same component.

### 4. Verify

```bash
kubectl get nodes
kubectl get pods -A | grep -v Running
```

Check that ArgoCD apps are back to `Synced`/`Healthy` (some may briefly show `Progressing` while `kubelet` restarts roll pods).

## Talos OS upgrade

### 1. Check current version

```bash
talosctl version --nodes 10.40.0.5
```

### 2. Upgrade each node, one at a time

As of Talos 1.13+, `talosctl upgrade` drains the node's Kubernetes workloads client-side automatically before rebooting it, so no manual `kubectl cordon`/`drain`/`uncordon` is needed. Workers first, control-plane last (validated order: the single control-plane node's brief API downtime during its own reboot happens last, after the workers are already on the new version):

```bash
talosctl upgrade --nodes 10.40.0.6 --image ghcr.io/siderolabs/installer:v<TALOS_VERSION>
talosctl upgrade --nodes 10.40.0.7 --image ghcr.io/siderolabs/installer:v<TALOS_VERSION>
talosctl upgrade --nodes 10.40.0.5 --image ghcr.io/siderolabs/installer:v<TALOS_VERSION>
```

Each command waits for its node to pass its post-upgrade health check before returning (`post check passed`).

### 3. Verify

```bash
talosctl version --nodes 10.40.0.5,10.40.0.6,10.40.0.7
kubectl get nodes
```
