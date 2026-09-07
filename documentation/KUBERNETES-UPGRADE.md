# Talos & Kubernetes upgrades

Cluster:

* 1 control-plane: `kcontrol.khaddict.lab - 10.40.0.5`
* 2 workers:

  * `kworker01.khaddict.lab - 10.40.0.6`
  * `kworker02.khaddict.lab - 10.40.0.7`

All commands below run from `kcli.khaddict.lab`, which holds `talosconfig` & `kubeconfig`.

There are two independent upgrades:

1. The **Talos OS** running on the nodes (`talosctl upgrade`)
2. The **Kubernetes version** running on top of it (`talosctl upgrade-k8s`)

If the target Kubernetes version requires a newer Talos release, upgrade **Talos first**, then Kubernetes.

Do not skip minor versions when upgrading either Talos or Kubernetes.

---

## Pre-flight checks

Check the current state of the cluster:

```bash
talosctl version --client
talosctl version --nodes 10.40.0.5
kubectl get nodes -o wide
```

Check Talos cluster health:

```bash
talosctl health \
  --nodes 10.40.0.5 \
  --control-plane-nodes 10.40.0.5 \
  --worker-nodes 10.40.0.6,10.40.0.7
```

`talosctl health` requires exactly one node as the command target. The full control-plane and worker lists are supplied separately.

Everything should report `OK` before starting an upgrade.

### Backup etcd

Before upgrading Talos or Kubernetes, take an etcd snapshot:

```bash
talosctl --nodes 10.40.0.5 \
  etcd snapshot ./etcd-before-upgrade.snapshot
ls -lh ./etcd-before-upgrade.snapshot
```

Keep the snapshot somewhere safe until the upgrade has been fully validated.

---

## Talos OS upgrade

### 1. Check current versions

```bash
talosctl version --client
talosctl version --nodes 10.40.0.5
kubectl get nodes -o wide
```

The `talosctl` client can be newer than the Talos version currently running on the nodes.

`talosctl` on `kcli` is Salt-managed:

* state: `role/kcli/init.sls`
* version pin: `data/versions.yaml`
* updates tracked by Renovate

If needed, bump the Talos version in `data/versions.yaml`, then:

```bash
salt-call state.highstate
talosctl version --client
```

### 2. Installer image

Starting with Talos 1.14, `talosctl upgrade` defaults to an installer image from the **Talos Image Factory** instead of the old:

```text
ghcr.io/siderolabs/installer:v<VERSION>
```

Check the image selected by the current client with:

```bash
talosctl upgrade --help | grep -A2 -B2 image
```

Example with Talos 1.14:

```text
factory.talos.dev/metal-installer/<SCHEMATIC_ID>:v1.14.0
```

For this cluster, which uses the standard `metal` platform without additional system extensions, the default image selected by `talosctl` can be used directly.

If a node uses custom system extensions or a custom Image Factory schematic, make sure the upgrade image preserves that schematic before upgrading.

### 3. Upgrade each node, one at a time

`talosctl upgrade` drains the node's Kubernetes workloads automatically before rebooting it (`--drain` defaults to `true`), then waits for the node to return and uncordons it.

No manual:

```text
kubectl cordon
kubectl drain
kubectl uncordon
```

is normally required.

Upgrade the workers first, then the single control-plane last.

This keeps the Kubernetes API available while the workers are upgraded; the brief API outage caused by rebooting the only control-plane happens at the end.

#### Worker 1

```bash
talosctl upgrade --nodes 10.40.0.6
```

Wait for:

```text
post check passed
node uncordoned
```

Verify:

```bash
talosctl version --nodes 10.40.0.6
kubectl get node kworker01 -o wide
```

The node should be `Ready` and report the new Talos version.

#### Worker 2

```bash
talosctl upgrade --nodes 10.40.0.7
```

Verify:

```bash
talosctl version --nodes 10.40.0.7
kubectl get node kworker02 -o wide
```

#### Control-plane

Make sure both workers are `Ready` first:

```bash
kubectl get nodes -o wide
```

Then upgrade the control-plane:

```bash
talosctl upgrade --nodes 10.40.0.5
```

Because this cluster has a single control-plane node, expect a brief Kubernetes API outage while it reboots.

Verify:

```bash
talosctl version --nodes 10.40.0.5
kubectl get nodes -o wide
```

### 4. Verify Talos upgrade

Check all Talos versions:

```bash
talosctl version \
  --nodes 10.40.0.5,10.40.0.6,10.40.0.7
```

Check Kubernetes nodes:

```bash
kubectl get nodes -o wide
```

Then run a full health check:

```bash
talosctl health \
  --nodes 10.40.0.5 \
  --control-plane-nodes 10.40.0.5 \
  --worker-nodes 10.40.0.6,10.40.0.7
```

Do not start the Kubernetes upgrade until the cluster is fully healthy again.

---

## Kubernetes version upgrade

### 1. Check current versions

```bash
talosctl version --client
kubectl version
kubectl get nodes -o wide
```

### 2. Make sure Talos and talosctl support the target version

`talosctl upgrade-k8s` refuses Kubernetes versions it does not know about.

The supported upgrade paths are part of the `talosctl` client version. If the target Kubernetes release is newer than the installed client, `upgrade-k8s` may fail with:

```text
unsupported upgrade path
```

even for a normal one-minor-version upgrade.

Check the component versions supported by the relevant Talos release before upgrading, in the "Component Updates" section of the [Talos release notes](https://github.com/siderolabs/talos/releases).

`talosctl` on `kcli` is Salt-managed:

* state: `role/kcli/init.sls`
* version pin: `data/versions.yaml`
* updates tracked by Renovate

If necessary, bump `data/versions.yaml`, then:

```bash
salt-call state.highstate
talosctl version --client
```

The Talos version installed on **every node** must also support the target Kubernetes version.

### 3. Dry-run

Kubernetes upgrades must be performed one minor version at a time.

Before applying the upgrade, run:

```bash
talosctl upgrade-k8s \
  --nodes 10.40.0.5 \
  --to <TARGET_VERSION> \
  --dry-run
```

The dry-run:

* discovers the control-plane and worker nodes
* verifies Talos/Kubernetes compatibility on every node
* checks for removed Kubernetes component flags
* checks for removed Kubernetes API resource versions
* shows which control-plane components will be updated
* shows the kubelet updates for every node
* shows changes to Talos-managed bootstrap manifests

Review the output before proceeding.

Changes to Talos-managed components such as `kube-proxy`, Flannel or CoreDNS can be expected when the new Talos/Kubernetes versions ship updated bootstrap manifests.

### 4. Run the upgrade

If the dry-run is clean:

```bash
talosctl upgrade-k8s \
  --nodes 10.40.0.5 \
  --to <TARGET_VERSION>
```

Only one control-plane node needs to be specified.

A single command handles the complete cluster.

It updates, in order:

* `kube-apiserver`
* `kube-controller-manager`
* `kube-scheduler`
* `kube-proxy`
* `kubelet` on the control-plane
* `kubelet` on each worker
* Talos-managed Kubernetes bootstrap manifests

During control-plane component updates, expect repeated messages such as:

```text
waiting, config version mismatch: got "N", expected "N+1"
```

or:

```text
pod is not ready, waiting
```

This is normal polling while Talos patches the machine configuration, regenerates the static pod and waits for the new component to become ready.

Investigate only if the command stops making progress for an abnormal amount of time.

The upgrade completes with:

```text
waiting for kubernetes objects to be fully reconciled
done
```

### 5. Verify Kubernetes upgrade

Check node versions:

```bash
kubectl get nodes -o wide
```

All nodes should be `Ready` and report the target Kubernetes version.

Check for pods which are not `Running` or `Completed`:

```bash
kubectl get pods -A | grep -vE 'Running|Completed'
```

If only the table header is returned, there are no obvious unhealthy pods.

Check ArgoCD and make sure applications return to:

```text
Synced
Healthy
```

Some applications may briefly report `Progressing` while kubelet restarts cause pods to roll.

Finally, run the Talos health check:

```bash
talosctl health \
  --nodes 10.40.0.5 \
  --control-plane-nodes 10.40.0.5 \
  --worker-nodes 10.40.0.6,10.40.0.7
```

Everything should report `OK`.

---

## Validated upgrade example

Validated on this cluster:

```text
Before:
  Talos:      1.13.6
  Kubernetes: 1.36.2

After:
  Talos:      1.14.0
  Kubernetes: 1.37.0
```

Sequence used:

```text
1. Check cluster health
2. Snapshot etcd
3. Upgrade kworker01 to Talos 1.14.0
4. Verify kworker01
5. Upgrade kworker02 to Talos 1.14.0
6. Verify kworker02
7. Upgrade kcontrol to Talos 1.14.0
8. Verify full Talos cluster health
9. Run Kubernetes 1.37.0 dry-run
10. Upgrade Kubernetes 1.36.2 -> 1.37.0
11. Verify nodes and pods
12. Verify full Talos cluster health
```

Final validated state:

```text
kcontrol    Talos 1.14.0    Kubernetes 1.37.0    Ready
kworker01   Talos 1.14.0    Kubernetes 1.37.0    Ready
kworker02   Talos 1.14.0    Kubernetes 1.37.0    Ready
```
