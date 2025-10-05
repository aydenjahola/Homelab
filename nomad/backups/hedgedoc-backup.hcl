job "hedgedoc-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "odin"
  }

  periodic {
    crons            = ["0 */6 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "backup" {
    count = 1

    task "hedgedoc-db-backup" {
      driver = "docker"

      config {
        image   = "postgres:16-alpine"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing curl + gnupg + rclone ..."
apk add --no-cache curl gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

: "$DB_HOST"
: "$DB_PORT"
: "$POSTGRES_USER"
: "$POSTGRES_PASSWORD"
: "$POSTGRES_DB"
: "$GPG_RECIPIENT"
: "$RETENTION_DAYS"
: "$DISCORD_WEBHOOK_URL"

export PGPASSWORD="$POSTGRES_PASSWORD"

notify_ok() {
  msg="$*"
  curl -sS -H "Content-Type: application/json" \
    -d "$(printf '{"content":"%s"}' "$msg")" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

notify_fail() {
  msg="$*"
  payload="$(printf '{"content":"%s","allowed_mentions":{"users":["367293674981294086"]}}' "$msg")"
  curl -sS -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

trap 'notify_fail "❌ <@367293674981294086> **hedgedoc-backup** failed on $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ). Check Nomad alloc logs."' ERR

DATE="$(date -u +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="hedgedoc-backup-$DATE.sql.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/hedgedoc"

echo "==> Dumping database $POSTGRES_DB@$DB_HOST:$DB_PORT ..."
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges \
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
notify_ok "✅ **hedgedoc-backup** finished on \`$(hostname)\` at \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`. File: \`$BASENAME.gpg\` uploaded to \`$REMOTE\`."
SCRIPT
        ]

        volumes = [
          "/home/ayden/.config/rclone/rclone.conf:/local/rclone.conf:ro",
          "/home/ayden/.gnupg:/gnupg:ro",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER={{ key "hedgedoc/db/user" }}
POSTGRES_PASSWORD={{ key "hedgedoc/db/password" }}
POSTGRES_DB={{ key "hedgedoc/db/name" }}

GPG_RECIPIENT={{ key "backup/gpg/key" }}
RETENTION_DAYS={{ key "backup/retention/days" }}
DISCORD_WEBHOOK_URL={{ key "backup/webhook/discord" }}
EOH
      }

      template {
        destination = "local/db.env"
        env         = true
        data        = <<EOH
{{- $svc := service "hedgedoc-db" -}}
{{- if gt (len $svc) 0 -}}
DB_HOST={{ (index $svc 0).Address }}
DB_PORT={{ (index $svc 0).Port }}
{{- end -}}
EOH
      }
    }
  }
}
