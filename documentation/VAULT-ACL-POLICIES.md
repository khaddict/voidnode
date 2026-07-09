# Vault ACL policies

Reference for the Vault policies used across the homelab. These are applied manually (`vault policy write <name> -`), not managed by Salt. There is no state in this repo that creates or updates them, so any change made here must also be applied by hand on `vault.khaddict.lab`.

## `saltmaster` policy

Attached to the saltmaster's own Vault AppRole. Lets the saltmaster manage the `salt-minions` auth method and its associated identities: creating/reading/deleting minion roles, looking up and creating entities/entity-aliases. This is what allows a new minion to be onboarded (accepted into `salt-minions` auth) without needing a human to touch Vault directly.

```hcl
path "auth/salt-minions/role" {
  capabilities = ["list"]
}

path "auth/salt-minions/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/auth/salt-minions" {
  capabilities = ["read", "sudo"]
}

path "identity/lookup/entity" {
  capabilities = ["create", "update"]
}

path "identity/entity/name" {
  capabilities = ["list"]
}

path "identity/entity/name/salt_minion_*" {
  capabilities = ["read", "create", "update", "delete"]
}

path "identity/entity-alias" {
  capabilities = ["create", "update"]
}
```

## `minion-isolated` policy

Attached to every regular minion's identity via `{{identity.entity.metadata.minion-id}}` templating. Each minion can only read its own secrets under `kv/minions/<its-own-id>/*`, plus anything under `kv/shared/*`. This is what keeps one minion from reading another minion's secrets even though they all authenticate through the same `salt-minions` auth method.

```hcl
path "kv/data/minions/{{identity.entity.metadata.minion-id}}/*" {
  capabilities = ["read"]
}

path "kv/metadata/minions/{{identity.entity.metadata.minion-id}}/*" {
  capabilities = ["read", "list"]
}

path "kv/data/shared/*" {
  capabilities = ["read"]
}

path "kv/metadata/shared/*" {
  capabilities = ["read", "list"]
}
```

Verification example (`netbox` and `registry` minions, confirming each is denied the other's secrets):

```
[Sat 21 Mar - 10:53:36] [root@saltmaster:~]
> salt 'netbox' vault.read_secret kv/minions/netbox/test
netbox:
    ----------
    foo:
        bar
[Sat 21 Mar - 10:53:46] [root@saltmaster:~]
> salt 'netbox' vault.read_secret kv/minions/registry/test
netbox:
    ERROR: Failed to read secret! VaultPermissionDeniedError: 1 error occurred:
        * permission denied

ERROR: Minions returned with non-zero exit code
[Sat 21 Mar - 10:53:53] [root@saltmaster:~] [✗ 1]
> salt 'registry' vault.read_secret kv/minions/registry/test
registry:
    ----------
    foo:
        bar
[Sat 21 Mar - 10:53:59] [root@saltmaster:~]
> salt 'registry' vault.read_secret kv/minions/netbox/test
registry:
    ERROR: Failed to read secret! VaultPermissionDeniedError: 1 error occurred:
        * permission denied

ERROR: Minions returned with non-zero exit code
```

## `kubernetes` policy

Attached to the Vault token/AppRole used by the ArgoCD Vault Plugin (AVP) inside the Kubernetes cluster. Grants read access to every app secret under `kv/kubernetes/*` (used by `<path:kv/data/kubernetes/<app>#FIELD>` placeholders in Helm values), plus the two specific EasyPKI-issued certs the cluster needs: the wildcard cert used by Envoy Gateway and the ArgoCD server cert. Scoped to exactly those two cert paths rather than all of `kv/minions/easypki/*`, so this policy can't read certs for other hosts.

```hcl
path "kv/data/kubernetes/*" {
  capabilities = ["read"]
}

path "kv/metadata/kubernetes/*" {
  capabilities = ["list"]
}

path "kv/data/minions/easypki/server/wildcard-khaddict-lab" {
  capabilities = ["read"]
}

path "kv/metadata/minions/easypki/server/wildcard-khaddict-lab" {
  capabilities = ["list"]
}

path "kv/data/minions/easypki/chain" {
  capabilities = ["read"]
}

path "kv/metadata/minions/easypki/chain" {
  capabilities = ["list"]
}

path "kv/data/minions/easypki/server/argocd.khaddict.lab" {
  capabilities = ["read"]
}

path "kv/metadata/minions/easypki/server/argocd.khaddict.lab" {
  capabilities = ["list"]
}
```

## Adding a new path

When a new component needs a new EasyPKI cert or Vault secret, add the specific `kv/data/...` (and matching `kv/metadata/...` for listing) path to the relevant policy above, then re-apply it by hand with `vault policy write`. Avoid broadening a policy to a wildcard covering more than the component actually needs.
