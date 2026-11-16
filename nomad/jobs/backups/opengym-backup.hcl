job "opengym-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["30 3 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "backup" {
    count = 1

    # openGym keeps everything in JSON files (no database): archive the data dir.
    task "opengym-data-backup" {
      driver = "docker"

      config {
        image   = "alpine:3.24.4"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing packages (curl, gnupg, rclone) ..."
apk add --no-cache curl gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

: "$GPG_RECIPIENT"
: "$RETENTION_DAYS"
: "$DISCORD_WEBHOOK_URL"
: "$NTFY_URL"
: "$NTFY_TOKEN"

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
}

notify_fail() {
  msg="$*"
  payload="$(printf '{"content":"%s","allowed_mentions":{"users":["367293674981294086"]}}' "$msg")"
  curl -sS -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
  ntfy 4 backup,failed "$*"
}

trap 'notify_fail "❌ <@367293674981294086> **opengym-backup** failed on $(hostname) at $(date +%Y-%m-%dT%H:%M:%SZ). Check Nomad alloc logs."' ERR

DATE="$(date +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="opengym-backup-$DATE.tar.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/opengym"

[ -f /data/db.json ] || { echo "no /data/db.json, refusing to back up an empty dir"; false; }

echo "==> Archiving /data ..."
tar -czf - -C / data \
  | gpg --batch --yes --trust-model always -r "$GPG_RECIPIENT" -o "$ENC_PATH" --encrypt

echo "==> Uploading to $REMOTE ..."
rclone copy --transfers=4 --checkers=8 --checksum "$ENC_PATH" "$REMOTE"

echo "==> Pruning remote backups older than $RETENTION_DAYS days ..."
AGE="$(printf '%sd' "$RETENTION_DAYS")"
rclone delete "$REMOTE" --min-age "$AGE" || true
rclone rmdirs "$REMOTE" --leave-root || true

echo "==> Cleaning local artifacts ..."
rm -f "$ENC_PATH" || true

echo "==> Backup finished."
notify_ok "✅ **opengym-backup** finished on \`$(hostname)\` at \`$(date +%Y-%m-%dT%H:%M:%SZ)\`. File: \`$BASENAME.gpg\` uploaded to \`$REMOTE\`."
SCRIPT
        ]

        volumes = [
          "/storage/nomad/opengym/api:/data:ro",
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
GPG_RECIPIENT       = {{ key "backup/gpg/key" }}
RETENTION_DAYS      = {{ key "backup/retention/days" }}
DISCORD_WEBHOOK_URL = {{ key "backup/webhook/discord" }}
NTFY_URL            = {{ key "ntfy/url" }}
NTFY_TOKEN          = {{ key "ntfy/token/backups" }}
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
