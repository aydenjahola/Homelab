job "vaultwarden-backup" {
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

    task "vaultwarden-db-backup" {
      driver = "docker"

      config {
        image   = "alpine:3.20"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing sqlite + gnupg + rclone ..."
apk add --no-cache sqlite gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

DATE="$(date -u +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="vaultwarden-backup-$DATE.sql.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/vaultwarden"

DB_PATH="/data/db.sqlite3"

echo "==> Dumping SQLite database ($DB_PATH) ..."
# Create a consistent SQL dump and compress it
sqlite3 "$DB_PATH" ".timeout 5000" ".dump" | gzip -c > "$PLAIN_PATH"

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
SCRIPT
        ]

        volumes = [
          "/home/ayden/.config/rclone/rclone.conf:/local/rclone.conf:ro",
          "/home/ayden/.gnupg:/gnupg:ro",
          "/storage/nomad/vaultwarden:/data:ro",
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
GPG_RECIPIENT={{ key "backup/gpg/key" }}
RETENTION_DAYS={{ key "backup/retention/days" }}
EOH
      }
    }
  }
}
