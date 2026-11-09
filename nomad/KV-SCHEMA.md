# Consul KV schema

Keys that Nomad jobs and Authentik blueprints read via `key` / `keyOrDefault`.
Generated from `scripts/kv-check.sh --markdown`; verify existence with `scripts/kv-check.sh --check`.
Only key names are documented here, never values. **secret** marks keys that hold credentials.

### `jobs/backups/authentik-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/db/name` |  | authentik database name |
| `authentik/db/password` | secret | authentik database password |
| `authentik/db/user` |  | authentik database user |
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |

### `jobs/backups/bazarr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `bazarr/db/name` |  | bazarr database name |
| `bazarr/db/password` | secret | bazarr database password |
| `bazarr/db/user` |  | bazarr database user |

### `jobs/backups/dependency-track-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `dependency-track/db/name` |  | dependency-track database name |
| `dependency-track/db/password` | secret | dependency-track database password |
| `dependency-track/db/user` |  | dependency-track database user |

### `jobs/backups/hedgedoc-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `hedgedoc/db/name` |  | hedgedoc database name |
| `hedgedoc/db/password` | secret | hedgedoc database password |
| `hedgedoc/db/user` |  | hedgedoc database user |

### `jobs/backups/homarr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `homarr/db/name` |  | homarr database name |
| `homarr/db/password` | secret | homarr database password |
| `homarr/db/user` |  | homarr database user |

### `jobs/backups/jellyfin-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `jellyfin/db/name` |  | jellyfin database name |
| `jellyfin/db/password` | secret | jellyfin database password |
| `jellyfin/db/user` |  | jellyfin database user |

### `jobs/backups/plausible-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `plausible/db/name` |  | plausible database name |
| `plausible/db/password` | secret | plausible database password |
| `plausible/db/user` |  | plausible database user |

### `jobs/backups/prowlarr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `prowlarr/db/main` |  | prowlarr db main |
| `prowlarr/db/password` | secret | prowlarr database password |
| `prowlarr/db/user` |  | prowlarr database user |

### `jobs/backups/radarr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `radarr/db/main` |  | radarr db main |
| `radarr/db/password` | secret | radarr database password |
| `radarr/db/user` |  | radarr database user |

### `jobs/backups/seerr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `seerr/db/name` |  | seerr database name |
| `seerr/db/password` | secret | seerr database password |
| `seerr/db/user` |  | seerr database user |

### `jobs/backups/sonarr-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `sonarr/db/main` |  | sonarr db main |
| `sonarr/db/password` | secret | sonarr database password |
| `sonarr/db/user` |  | sonarr database user |

### `jobs/backups/uptime-kuma-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `uptime-kuma/db/name` |  | uptime-kuma database name |
| `uptime-kuma/db/password` | secret | uptime-kuma database password |
| `uptime-kuma/db/root/password` | secret | uptime-kuma database root password |
| `uptime-kuma/db/user` |  | uptime-kuma database user |

### `jobs/backups/vaultwarden-backup.hcl`

| Key | Secret | Description |
|---|---|---|
| `backup/gpg/key` | secret | GPG key used to encrypt backups |
| `backup/retention/days` |  | Number of days to keep backups |
| `backup/webhook/discord` | secret | Discord webhook URL for backup notifications |
| `vaultwarden/db/name` |  | vaultwarden database name |
| `vaultwarden/db/password` | secret | vaultwarden database password |
| `vaultwarden/db/user` |  | vaultwarden database user |

### `jobs/ingress/keepalived.hcl`

| Key | Secret | Description |
|---|---|---|
| `keepalived/auth/pass` | secret | VRRP authentication password |

### `jobs/ingress/traefik.hcl`

| Key | Secret | Description |
|---|---|---|
| `traefik/cf/api` | secret | Cloudflare API key for ACME DNS challenge |
| `traefik/cf/email` |  | Cloudflare account email for ACME DNS challenge |

### `jobs/media/bazarr.hcl`

| Key | Secret | Description |
|---|---|---|
| `bazarr/db/name` |  | bazarr database name |
| `bazarr/db/password` | secret | bazarr database password |
| `bazarr/db/user` |  | bazarr database user |

### `jobs/media/jellyfin.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/jellyfin/client_id` | secret | OIDC client id for the jellyfin Authentik provider |
| `authentik/oidc/jellyfin/client_secret` | secret | OIDC client secret for the jellyfin Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `jellyfin/db/name` |  | jellyfin database name |
| `jellyfin/db/password` | secret | jellyfin database password |
| `jellyfin/db/user` |  | jellyfin database user |

### `jobs/media/prowlarr.hcl`

| Key | Secret | Description |
|---|---|---|
| `prowlarr/db/log` |  | prowlarr db log |
| `prowlarr/db/main` |  | prowlarr db main |
| `prowlarr/db/password` | secret | prowlarr database password |
| `prowlarr/db/user` |  | prowlarr database user |

### `jobs/media/radarr.hcl`

| Key | Secret | Description |
|---|---|---|
| `radarr/db/log` |  | radarr db log |
| `radarr/db/main` |  | radarr db main |
| `radarr/db/password` | secret | radarr database password |
| `radarr/db/user` |  | radarr database user |

### `jobs/media/seerr.hcl`

| Key | Secret | Description |
|---|---|---|
| `seerr/db/name` |  | seerr database name |
| `seerr/db/password` | secret | seerr database password |
| `seerr/db/user` |  | seerr database user |

### `jobs/media/sonarr.hcl`

| Key | Secret | Description |
|---|---|---|
| `sonarr/db/log` |  | sonarr db log |
| `sonarr/db/main` |  | sonarr db main |
| `sonarr/db/password` | secret | sonarr database password |
| `sonarr/db/user` |  | sonarr database user |

### `jobs/media/tracearr.hcl`

| Key | Secret | Description |
|---|---|---|
| `tracearr/app/cookie/secret` | secret | tracearr app cookie secret |
| `tracearr/app/jwt/secret` | secret | tracearr app jwt secret |
| `tracearr/db/name` |  | tracearr database name |
| `tracearr/db/password` | secret | tracearr database password |
| `tracearr/db/user` |  | tracearr database user |

### `jobs/monitoring/diun.hcl`

| Key | Secret | Description |
|---|---|---|
| `diun/discord/webhook` | secret | diun discord webhook |
| `docker/ghcr/token` | secret | GitHub Container Registry access token |
| `docker/ghcr/user` |  | GitHub Container Registry username |
| `docker/hub/token` | secret | Docker Hub access token |
| `docker/hub/user` |  | Docker Hub username |

### `jobs/monitoring/gatus.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `gatus/db/name` |  | gatus database name |
| `gatus/db/password` | secret | gatus database password |
| `gatus/db/user` |  | gatus database user |
| `gatus/discord/webhook/url` | secret | gatus discord webhook url |

### `jobs/monitoring/grafana.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/grafana/client_id` | secret | OIDC client id for the grafana Authentik provider |
| `authentik/oidc/grafana/client_secret` | secret | OIDC client secret for the grafana Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |

### `jobs/monitoring/netronome.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/netronome/client_id` | secret | OIDC client id for the netronome Authentik provider |
| `authentik/oidc/netronome/client_secret` | secret | OIDC client secret for the netronome Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `netronome/db/name` |  | netronome database name |
| `netronome/db/password` | secret | netronome database password |
| `netronome/db/user` |  | netronome database user |
| `netronome/session/secret` | secret | netronome session signing secret |

### `jobs/monitoring/uptime-kuma.hcl`

| Key | Secret | Description |
|---|---|---|
| `uptime-kuma/db/name` |  | uptime-kuma database name |
| `uptime-kuma/db/password` | secret | uptime-kuma database password |
| `uptime-kuma/db/root/password` | secret | uptime-kuma database root password |
| `uptime-kuma/db/user` |  | uptime-kuma database user |

### `jobs/monitoring/watchyourlan.hcl`

| Key | Secret | Description |
|---|---|---|
| `watchyourlan/ifaces` |  | Network interfaces WatchYourLAN scans |
| `watchyourlan/shoutrrr/url` | secret | Shoutrrr notification URL |

### `jobs/security/cve-scan.hcl`

| Key | Secret | Description |
|---|---|---|
| `cve-scan/discord/webhook` | secret | Discord webhook for CVE scan reports |
| `cve-scan/dtrack/api-key` | secret | Dependency-Track API key used to upload scan results |
| `docker/ghcr/token` | secret | GitHub Container Registry access token |
| `docker/ghcr/user` |  | GitHub Container Registry username |
| `docker/hub/token` | secret | Docker Hub access token |
| `docker/hub/user` |  | Docker Hub username |
| `cve-scan/nomad/token` | secret | Nomad ACL token for listing jobs (optional) (optional, has default) |

### `jobs/security/dependency-track.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/dependency-track/client_id` | secret | OIDC client id for the dependency-track Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `dependency-track/db/name` |  | dependency-track database name |
| `dependency-track/db/password` | secret | dependency-track database password |
| `dependency-track/db/user` |  | dependency-track database user |

### `jobs/security/trivy-server.hcl`

| Key | Secret | Description |
|---|---|---|
| `trivy/server/token` | secret | Shared auth token for the Trivy server |

### `jobs/services/authentik/authentik.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/bootstrap/email` |  | Initial Authentik admin (akadmin) email |
| `authentik/bootstrap/password` | secret | Initial Authentik admin (akadmin) password |
| `authentik/db/name` |  | authentik database name |
| `authentik/db/password` | secret | authentik database password |
| `authentik/db/user` |  | authentik database user |
| `authentik/secret/key` | secret | Authentik signing/encryption secret key |
| `authentik/smtp/from` |  | authentik SMTP sender address |
| `authentik/smtp/host` |  | authentik SMTP server host |
| `authentik/smtp/password` | secret | authentik SMTP password |
| `authentik/smtp/port` |  | authentik SMTP server port |
| `authentik/smtp/username` |  | authentik SMTP username |

### `jobs/services/authentik/blueprints/app-asf.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-bazarr.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-dependency-track.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/dependency-track/client_id` | secret | OIDC client id for the dependency-track Authentik provider |
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-docs.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-dozzle.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-grafana.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/grafana/client_id` | secret | OIDC client id for the grafana Authentik provider |
| `authentik/oidc/grafana/client_secret` | secret | OIDC client secret for the grafana Authentik provider |
| `homelab/domain` |  | Public base domain used to build external URLs |

### `jobs/services/authentik/blueprints/app-hedgedoc.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/hedgedoc/client_id` | secret | OIDC client id for the hedgedoc Authentik provider |
| `authentik/oidc/hedgedoc/client_secret` | secret | OIDC client secret for the hedgedoc Authentik provider |
| `homelab/domain` |  | Public base domain used to build external URLs |

### `jobs/services/authentik/blueprints/app-homarr.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/homarr/client_id` | secret | OIDC client id for the homarr Authentik provider |
| `authentik/oidc/homarr/client_secret` | secret | OIDC client secret for the homarr Authentik provider |
| `homelab/domain` |  | Public base domain used to build external URLs |

### `jobs/services/authentik/blueprints/app-jellyfin.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/jellyfin/client_id` | secret | OIDC client id for the jellyfin Authentik provider |
| `authentik/oidc/jellyfin/client_secret` | secret | OIDC client secret for the jellyfin Authentik provider |
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-netronome.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/netronome/client_id` | secret | OIDC client id for the netronome Authentik provider |
| `authentik/oidc/netronome/client_secret` | secret | OIDC client secret for the netronome Authentik provider |
| `homelab/domain` |  | Public base domain used to build external URLs |

### `jobs/services/authentik/blueprints/app-prometheus.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-prowlarr.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-radarr.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-reactive-resume.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/reactive-resume/client_id` | secret | OIDC client id for the reactive-resume Authentik provider |
| `authentik/oidc/reactive-resume/client_secret` | secret | OIDC client secret for the reactive-resume Authentik provider |
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-seerr.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/seerr/client_id` | secret | OIDC client id for the seerr Authentik provider |
| `authentik/oidc/seerr/client_secret` | secret | OIDC client secret for the seerr Authentik provider |
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-sonarr.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-tracearr.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-vaultwarden.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/vaultwarden/client_id` | secret | OIDC client id for the vaultwarden Authentik provider |
| `authentik/oidc/vaultwarden/client_secret` | secret | OIDC client secret for the vaultwarden Authentik provider |
| `homelab/domain` |  | Public base domain used to build external URLs |

### `jobs/services/authentik/blueprints/app-watchyourlan.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/app-ylfm.yaml`

| Key | Secret | Description |
|---|---|---|
| `homelab/domain_local` |  | Internal/LAN base domain used to build service URLs |

### `jobs/services/authentik/blueprints/homelab-base.yaml`

| Key | Secret | Description |
|---|---|---|
| `authentik/user/email` |  | Email of the default homelab user created by the base blueprint |
| `authentik/user/name` |  | Display name of the default homelab user |
| `authentik/user/username` |  | Username of the default homelab user |

### `jobs/services/cloudflare-ddns.hcl`

| Key | Secret | Description |
|---|---|---|
| `cloudflare/api/key` | secret | Cloudflare API token for DDNS |
| `cloudflare/zone` |  | Cloudflare zone ID or name for DDNS updates |

### `jobs/services/hedgedoc.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/hedgedoc/client_id` | secret | OIDC client id for the hedgedoc Authentik provider |
| `authentik/oidc/hedgedoc/client_secret` | secret | OIDC client secret for the hedgedoc Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `hedgedoc/allow/annonymous` |  | hedgedoc allow annonymous |
| `hedgedoc/allow/gravatar` |  | hedgedoc allow gravatar |
| `hedgedoc/db/name` |  | hedgedoc database name |
| `hedgedoc/db/password` | secret | hedgedoc database password |
| `hedgedoc/db/user` |  | hedgedoc database user |
| `hedgedoc/session/secret` | secret | hedgedoc session signing secret |
| `hedgedoc/ssl` |  | hedgedoc ssl |

### `jobs/services/homarr.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/homarr/client_id` | secret | OIDC client id for the homarr Authentik provider |
| `authentik/oidc/homarr/client_secret` | secret | OIDC client secret for the homarr Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `homarr/db/dialect` |  | homarr database dialect |
| `homarr/db/driver` |  | homarr database driver |
| `homarr/db/name` |  | homarr database name |
| `homarr/db/password` | secret | homarr database password |
| `homarr/db/user` |  | homarr database user |
| `homarr/default/color` |  | homarr default color |
| `homarr/edit/disable` |  | homarr edit disable |
| `homarr/edit/password` | secret | homarr edit password |
| `homarr/encryption/key` | secret | homarr encryption key |

### `jobs/services/plausible.hcl`

| Key | Secret | Description |
|---|---|---|
| `plausible/db/name` |  | plausible database name |
| `plausible/db/password` | secret | plausible database password |
| `plausible/db/user` |  | plausible database user |
| `plausible/google/client/id` |  | plausible google client id |
| `plausible/google/client/secret` | secret | plausible google client secret |
| `plausible/maxmind/license` | secret | plausible maxmind license |
| `plausible/secret/key` | secret | plausible application secret key |
| `plausible/smtp/from` |  | plausible SMTP sender address |
| `plausible/smtp/host` |  | plausible SMTP server host |
| `plausible/smtp/name` |  | plausible SMTP sender name |
| `plausible/smtp/password` | secret | plausible SMTP password |
| `plausible/smtp/port` |  | plausible SMTP server port |
| `plausible/smtp/username` |  | plausible SMTP username |
| `plausible/totp/key` | secret | plausible totp key |

### `jobs/services/reactive-resume.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/reactive-resume/client_id` | secret | OIDC client id for the reactive-resume Authentik provider |
| `authentik/oidc/reactive-resume/client_secret` | secret | OIDC client secret for the reactive-resume Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `reactive-resume/auth/secret` | secret | reactive-resume auth signing secret |
| `reactive-resume/db/name` |  | reactive-resume database name |
| `reactive-resume/db/password` | secret | reactive-resume database password |
| `reactive-resume/db/user` |  | reactive-resume database user |
| `reactive-resume/smtp/host` |  | reactive-resume SMTP server host |
| `reactive-resume/smtp/password` | secret | reactive-resume SMTP password |
| `reactive-resume/smtp/user` |  | reactive-resume SMTP username |

### `jobs/services/vaultwarden.hcl`

| Key | Secret | Description |
|---|---|---|
| `authentik/oidc/vaultwarden/client_id` | secret | OIDC client id for the vaultwarden Authentik provider |
| `authentik/oidc/vaultwarden/client_secret` | secret | OIDC client secret for the vaultwarden Authentik provider |
| `authentik/url` |  | Base URL of the Authentik server (OIDC issuer / app links) |
| `vaultwarden/admin/token` | secret | vaultwarden admin token |
| `vaultwarden/db/name` |  | vaultwarden database name |
| `vaultwarden/db/password` | secret | vaultwarden database password |
| `vaultwarden/db/user` |  | vaultwarden database user |
| `vaultwarden/domain` |  | vaultwarden domain |
| `vaultwarden/install/id` | secret | vaultwarden install id |
| `vaultwarden/install/key` | secret | vaultwarden install key |
| `vaultwarden/smtp/from` |  | vaultwarden SMTP sender address |
| `vaultwarden/smtp/host` |  | vaultwarden SMTP server host |
| `vaultwarden/smtp/password` | secret | vaultwarden SMTP password |
| `vaultwarden/smtp/port` |  | vaultwarden SMTP server port |
| `vaultwarden/smtp/username` |  | vaultwarden SMTP username |

### `jobs/services/ylfm.hcl`

| Key | Secret | Description |
|---|---|---|
| `your-lastfm/api/key` | secret | your-lastfm api key |
| `your-lastfm/username` |  | your-lastfm username |

### `jobs/websites/homelab-docs.hcl`

| Key | Secret | Description |
|---|---|---|
| `docker/ghcr/token` | secret | GitHub Container Registry access token |
| `docker/ghcr/user` |  | GitHub Container Registry username |
