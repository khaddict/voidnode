## saltmaster policy
```
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

## minion-isolated policy
```
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

## kubernetes policy
```
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
```