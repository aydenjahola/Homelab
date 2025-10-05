job "linkwarden-backup" {
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

    task "linkwarden-postgres-backup" {
      driver = "docker"

      config {
        image   = "postgres:16-alpine"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing dependencies (gnupg, rclone, curl) ..."
apk add --no-cache gnupg rclone ca-certificates curl >/dev/null

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

notify() {
  status="$1"; shift
  msg="$*"
  curl -sS -H "Content-Type: application/json" \
    -d "$(printf '{"content":"%s"}' "$msg")" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

trap 'notify "fail" "❌ <@367293674981294086> **linkwarden-backup** failed on $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ). Check Nomad alloc logs."' ERR

DATE="$(date -u +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="linkwarden-postgres-$DATE.sql.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/linkwarden/postgres"

echo "==> Dumping Postgres $POSTGRES_DB@$DB_HOST:$DB_PORT ..."
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

notify "ok" "✅ **linkwarden-backup** finished on \`$(hostname)\` at \`$(date -u +'%Y-%m-%d %H:%M:%SZ')\`. File: \`$BASENAME.gpg\` uploaded to \`$REMOTE\`."
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
POSTGRES_USER={{ key "linkwarden/db/user" }}
POSTGRES_PASSWORD={{ key "linkwarden/db/password" }}
POSTGRES_DB={{ key "linkwarden/db/name" }}

GPG_RECIPIENT={{ key "backup/gpg/key" }}
RETENTION_DAYS={{ key "backup/retention/days" }}

DISCORD_WEBHOOK_URL={{ key "backup/webhook/discord" }}
EOH
      }

      template {
        destination = "local/db.env"
        env         = true
        data        = <<EOH
{{- $svcA := service "linkwarden-db" -}}
{{- $svcB := service "db" -}}
{{- if gt (len $svcA) 0 -}}
DB_HOST={{ (index $svcA 0).Address }}
DB_PORT={{ (index $svcA 0).Port }}
{{- else if gt (len $svcB) 0 -}}
DB_HOST={{ (index $svcB 0).Address }}
DB_PORT={{ (index $svcB 0).Port }}
{{- end -}}
EOH
      }
    }
  }
}
