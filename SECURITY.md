# Security

This documents the actual security posture of this homelab's infrastructure: what's enforced, what's an accepted risk, and why. It reflects the state after the audit remediation on 2026-08-15; update it whenever a security-relevant mechanism changes, not just when a new one is added.

## Secrets

All secrets live in HashiCorp Vault (`vault.khaddict.lab`). Nothing is committed in plaintext to this repo. Grep for `<path:kv/...>` (Salt Vault references) or `{{ var }}` (Jinja templates populated from a `salt['vault'].read_secret(...)` call) to find where a given secret is consumed.

- **Minion auth**: AppRole, one entity per minion, tagged with a `minion-id` metadata field. The `minion-isolated` Vault policy templates on that tag so, e.g., `netbox` cannot read `registry`'s secrets. See [documentation/VAULT-ACL-POLICIES.md](documentation/VAULT-ACL-POLICIES.md).
- **Kubernetes secrets**: injected at ArgoCD sync time by the ArgoCD Vault Plugin, authenticated with a long-lived Vault token.
- **Rotation**: rotate a secret in Vault, then re-run `state.apply` on whichever minion(s) consume it (or wait for ArgoCD's next sync for k8s-side secrets). There's no automated rotation schedule; this is a manual, as-needed process.

### Known accepted risks

- **Vault root token on disk** (`role/vault/init.sls`, `/root/.vault-token`, mode 600): persisted for operational convenience on the Vault host itself. Accepted risk, since the Vault VM is treated as the highest-trust host in the lab and hardened accordingly; a compromise there is already a total-loss scenario regardless of this file.
- **StackStorm workflow parameters aren't strictly validated** (`role/stackstorm/files/packs/st2_voidnode/actions/`): the `name` parameter reaches `qm`/`yq`/shell contexts without an allowlist pattern. Accepted risk, since the StackStorm API is bound to `127.0.0.1` with htpasswd auth and has no externally-triggerable webhook (only a `CronTimer` schedule), so exploitation requires an existing foothold on that host.
- **Vault `max_lease_ttl` is ~2 years** (`role/vault/files/vault.hcl`): long by production standards, accepted as reasonable for a single-operator homelab.
- **Loki has no authentication** (`role/loki/files/config.yml`, `auth_enabled: false`; note this setting is Loki's multi-tenancy header requirement, not real authentication either way). Reachable from anywhere already on the internal VLANs, not internet-exposed. A real fix would need a reverse proxy with basic auth in front of it, a coordinated secret rollout to every minion (Promtail on every host pushes to it via the `global` state), and a matching update to Grafana's Loki datasource (configured manually in the Grafana UI, not tracked in this repo). Accepted as-is for now given the limited blast radius.

## Network trust boundaries

Five VLANs behind OPNsense, least-privilege by default; see the main [README](README.md#network-architecture) for the full table. The one path worth calling out here: **EDGE can only reach Vault and SaltMaster**, plus a narrow, explicit exception for the `api` VM into the IOT VLAN (to drive the BUSY Bar). Nothing on IOT can initiate a connection anywhere, including the internet.

## The public API (`api.khaddict.com`)

- **Authentication**: none. `/wall/message` and `/wall/image` are intentionally public, so anyone can push a short message or image to the physical BUSY Bar display. The only protection is a per-IP rate limit.
- **Rate limiting**: a per-process, in-memory dict (`role/api/files/app/main.py`), correct only because gunicorn is pinned to a single worker. That invariant is enforced at startup: `role/api/files/gunicorn.py`'s `on_starting` hook raises and refuses to boot if `workers != 1`, so a future throughput "optimization" can't silently multiply the effective rate limit.
- **CORS**: an explicit origin allowlist (`http://website.khaddict.lab`, `http://www.website.khaddict.lab`, `https://www.khaddict.com`, `https://khaddict.com`), `GET`/`POST` only, no wildcard.
- **Uploads** (`/wall/image`): capped at 5MB pre-decompression, Pillow's `DecompressionBombError` explicitly caught, `Content-Type` checked against an allowlist (`image/png`/`jpeg`/`webp`) as a first filter, with actual image decoding as the real validation.
- **Reproducible deploys**: `role/api/files/requirements.lock.txt` is a full `pip freeze` pin (top-level and transitive), installed via a `virtualenv.managed` Salt state. Regenerate it after changing `requirements.txt`; see the comment at the top of the lockfile.
- **Docs**: `/docs` is the stock FastAPI/Swagger UI (unauthenticated, same capability as the endpoints themselves; hiding it wouldn't reduce actual attack surface). The domain root serves a separate, site-styled docs page maintained in the `khaddict-com` repo.

## Cross-repo trust: khaddict-com to voidnode

`khaddict-com`'s CI can write to this repo: `publish-chart.yaml` and `media-khaddict.yaml` each have a `bump-voidnode` job that uses a fine-grained PAT (`VOIDNODE_REPO_TOKEN`, `Contents: Read and write`, scoped to this repo only) to bump a version string and open a PR here, never a direct push. Two things keep this contained:

- The job that runs `khaddict-com`'s own build code is separate from the job holding the PAT (`needs:` dependency, only a plain version string crosses between them), so a compromised build step can't reach the credential.
- The bump job only runs `if: github.ref == 'refs/heads/main'`, so a manual `workflow_dispatch` against another branch can't reach it either.

Renovate no longer tracks the `khaddict-com` chart or the `media-khaddict` image (disabled in `.github/renovate.jsonc`); these two workflows are now the sole source of version bumps for those two dependencies, avoiding a race between the two mechanisms.

## Reporting an issue

Personal homelab, single maintainer. If you find something, open a GitHub Security Advisory on this repo rather than a public issue.
