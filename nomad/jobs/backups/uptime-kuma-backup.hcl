job "uptime-kuma-db-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */6 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "backup" {
    count = 1

    task "mariadb-backup" {
      driver = "docker"

      config {
        image   = "alpine:3.24.4"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing packages (mariadb-client, curl, gnupg, rclone) ..."
apk add --no-cache mariadb-client curl gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

: "$DB_HOST"
: "$DB_PORT"
: "$MYSQL_USER"
: "$MYSQL_PASSWORD"
: "$MYSQL_DATABASE"
: "$GPG_RECIPIENT"
: "$RETENTION_DAYS"
: "$DISCORD_WEBHOOK_URL"
: "$NTFY_URL"
: "$NTFY_TOKEN"

export MYSQL_PWD="$MYSQL_PASSWORD"

ntfy() {
  curl -sS -H "Authorization: Bearer $NTFY_TOKEN" \
    -H "Priority: $1" -H "Tags: $2" -H "Markdown: yes" \
    --data-binary "$(printf '%s' "$3" | sed 's/<@[0-9]*> //g')" \
    "$NTFY_URL/homelab-backups" >/dev/null || true
}

notify_ok() {
  msg="$*"
  curl -sS -H "Content-Type: application/json" \
    -d "$(printf '{"content":"%s"}' "$msg")" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
  ntfy 2 backup "$*"
}

notify_fail() {
  msg="$*"
  payload="$(printf '{"content":"%s","allowed_mentions":{"users":["367293674981294086"]}}' "$msg")"
  curl -sS -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
  ntfy 4 backup,failed "$*"
}

trap 'notify_fail "❌ <@367293674981294086> **uptime-kuma-db-backup** failed on $(hostname) at $(date +%Y-%m-%dT%H:%M:%SZ). Check Nomad alloc logs."' ERR

DATE="$(date +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="uptime-kuma-db-backup-$DATE.sql.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/uptime-kuma"

echo "==> Dumping MariaDB $MYSQL_DATABASE@$DB_HOST:$DB_PORT ..."
mysqldump --single-transaction --quick --lock-tables=false -h "$DB_HOST" -P "$DB_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" \
  | gzip -c > "$PLAIN_PATH"

echo "==> Encrypting for $GPG_RECIPIENT ..."
gpg --batch --yes --trust-model always -r "$GPG_RECIPIENT" -o "$ENC_PATH" --encrypt "$PLAIN_PATH"

echo "==> Uploading to $REMOTE ..."
rclone copy --transfers=4 --checkers=8 --checksum "$ENC_PATH" "$REMOTE"

echo "==> Pruning remote backups older than $RETENTION_DAYS days ..."
AGE="$(printf '%sd' "$RETENTION_DAYS")"
rclone delete "$REMOTE" --min-age "$AGE" || true
rclone rmdirs "$REMOTE" --leave-root || true

echo "==> Cleaning local artifacts ..."
shred -u -z "$PLAIN_PATH" || rm -f "$PLAIN_PATH"
rm -f "$ENC_PATH" || true

echo "==> Backup finished."
notify_ok "✅ **uptime-kuma-db-backup** finished on \`$(hostname)\` at \`$(date +%Y-%m-%dT%H:%M:%SZ)\`. File: \`$BASENAME.gpg\` uploaded to \`$REMOTE\`."
SCRIPT
        ]

        volumes = [
          "/home/ayden/.config/rclone/rclone.conf:/local/rclone.conf:ro",
          "/home/ayden/.gnupg:/gnupg:ro",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
MYSQL_ROOT_PASSWORD = {{ key "uptime-kuma/db/root/password" }}
MYSQL_DATABASE      = {{ key "uptime-kuma/db/name" }}
MYSQL_USER          = {{ key "uptime-kuma/db/user" }}
MYSQL_PASSWORD      = {{ key "uptime-kuma/db/password" }}

GPG_RECIPIENT       = {{ key "backup/gpg/key" }}
RETENTION_DAYS      = {{ key "backup/retention/days" }}
DISCORD_WEBHOOK_URL = {{ key "backup/webhook/discord" }}
NTFY_URL            = {{ key "ntfy/url" }}
NTFY_TOKEN          = {{ key "ntfy/token/backups" }}
EOH
      }

      template {
        destination = "local/db.env"
        env         = true
        data        = <<EOH
{{- $svc := service "uptime-kuma-db" -}}
{{- if gt (len $svc) 0 -}}
DB_HOST={{ (index $svc 0).Address }}
DB_PORT={{ (index $svc 0).Port }}
{{- end -}}
EOH
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 256
      }
    }
  }
}
