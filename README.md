# Homelab

Three-node Nomad and Consul cluster (Dell OptiPlex, Debian 13) with TrueNAS SCALE NFS at `/storage`, Traefik ingress behind a keepalived VIP, and Authentik SSO. Secrets live in Consul KV, never in the repo.

| Path | What |
|---|---|
| `ansible/` | Host config for odin, thor and loki (192.168.1.100-102) |
| `nomad/jobs/` | Nomad jobs by category; `backups/` has one backup job per stateful app |
| `nomad/jobs/services/authentik/blueprints/` | One Authentik app per file |
| `nomad/jobs/monitoring/grafana/` | Provisioned dashboards and alerting; edit `generate.py`, run it, commit the output |
| `nomad/scripts/kv-check.sh` | Lists and checks the Consul keys each job needs |

## Deploy

Run from `nomad/` (some jobs use paths relative to it). Updates are manual: Diun reports new tags, bump the pin, then plan and run.

```sh
cd nomad
nomad job plan jobs/media/jellyfin.hcl
nomad job run jobs/media/jellyfin.hcl
```

The scheduler uses `spread`. Running jobs never move on their own, so after a node has been offline run `scripts/rebalance.sh <busiest-node>`.

## New app checklist

- App group first, then a `db` group on `postgres:17-alpine` with a `wait-for-db` prestart task.
- Pinned image, `TZ = Europe/Dublin`, `memory` and `memory_max`, env templates `0600` with `error_on_missing_key`.
- Consul keys added (`nomad/scripts/kv-check.sh --check`), a backup job, a Gatus endpoint and an Authentik blueprint.

## Notifications

Self-hosted ntfy at `ntfy.aydenjahola.com`, login required. Senders publish with tokens from `ntfy/token/<sender>` to `homelab-alerts` (Grafana), `homelab-uptime` (Gatus), `homelab-backups`, `homelab-updates` (Diun) and `homelab-security` (cve-scan). Discord still receives the same alerts for now.

Backup successes are quiet: `backup-digest` posts one summary at 08:00, and `diun-digest` lists new image tags on Monday mornings. `truenas-alerts` forwards TrueNAS alerts to `homelab-alerts`.

## Hosts

```sh
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --check --diff     # drift check, expect 0 changed
ansible-playbook site.yml --diff -l <host>   # apply; runs serial to keep quorum
```

Rebuilding a wiped node: install Debian 13 with user `ayden`, keep its DHCP reservation, `ssh-copy-id`, run the playbook for that host. Remove the dead peer first (`consul operator raft remove-peer`, `nomad server force-leave`); Raft data replicates from the other two. Restarting Docker kills containers, so drain the node first.

## Backups and restore

App databases are dumped, GPG-encrypted and uploaded to Google Drive with rclone. `cluster-snapshot-backup` writes encrypted Consul and Nomad snapshots daily to `/storage/nomad/cluster-snapshot-backup/` and Google Drive. The private key stays on the Mac.

```sh
gpg --decrypt consul-<stamp>.snap.gpg > consul.snap
CONSUL_HTTP_ADDR=http://192.168.1.100:8500 consul snapshot restore consul.snap
gpg --decrypt nomad-<stamp>.snap.gpg > nomad.snap
NOMAD_ADDR=http://192.168.1.100:4646 nomad operator snapshot restore nomad.snap
```

After total loss, restore Consul first, then Nomad. Test restores against `-dev` agents, never the live cluster.

## CI

pre-commit (format, gitleaks, ansible-lint, `nomad fmt`) and `nomad job validate` on every job. Locally: `pre-commit install`.
