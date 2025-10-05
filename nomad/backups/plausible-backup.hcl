job "plausible-backup" {
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

    task "plausible-postgres-backup" {
      driver = "docker"

      config {
        image   = "postgres:16-alpine"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing gnupg + rclone ..."
apk add --no-cache gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_USER="$POSTGRES_USER"
DB_NAME="$POSTGRES_DB"
export PGPASSWORD="$POSTGRES_PASSWORD"

DATE="$(date -u +'%Y-%m-%d_%H-%M-%SZ')"
BASENAME="plausible-postgres-$DATE.sql.gz"
PLAIN_PATH="$NOMAD_TASK_DIR/$BASENAME"
ENC_PATH="$PLAIN_PATH.gpg"

REMOTE="gdrive:backups/plausible/postgres"

echo "==> Dumping Postgres $DB_NAME@$DB_HOST:$DB_PORT ..."
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --no-owner --no-privileges \
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

echo "==> Postgres backup finished."
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
POSTGRES_USER={{ key "plausible/db/user" }}
POSTGRES_PASSWORD={{ key "plausible/db/password" }}
POSTGRES_DB={{ key "plausible/db/name" }}

GPG_RECIPIENT={{ key "backup/gpg/key" }}
RETENTION_DAYS={{ key "backup/retention/days" }}
EOH
      }

      template {
        destination = "local/db.env"
        env         = true
        data        = <<EOH
{{- $svc := service "plausible-db" -}}
{{- if gt (len $svc) 0 -}}
DB_HOST={{ (index $svc 0).Address }}
DB_PORT={{ (index $svc 0).Port }}
{{- end -}}
EOH
      }
    }

    task "plausible-clickhouse-backup" {
      driver = "docker"

      config {
        image   = "alpine:3.20"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing curl + gnupg + rclone ..."
apk add --no-cache curl gnupg rclone ca-certificates >/dev/null

export RCLONE_CONFIG="/local/rclone.conf"
export GNUPGHOME="/gnupg"

CH_HOST="$CH_HOST"
CH_PORT="$CH_PORT"
CH_DB="$CLICKHOUSE_DB"

DATE="$(date -u +'%Y-%m-%d_%H-%M-%SZ')"
WORKDIR="$NOMAD_TASK_DIR/chdump-$DATE"
mkdir -p "$WORKDIR/schema" "$WORKDIR/data"

CH_URL="http://$CH_HOST:$CH_PORT/"

ue() { od -An -tx1 | tr -d ' \n' | sed 's/../%&/g'; }

echo "==> Listing ClickHouse tables in $CH_DB ..."
TABLES="$(curl -fsS "$CH_URL?query=$(printf %s "SELECT name FROM system.tables WHERE database = '$CH_DB' ORDER BY name FORMAT TSV" | ue)")"

printf 'CREATE DATABASE IF NOT EXISTS %s;\n' "$CH_DB" > "$WORKDIR/00_create_database.sql"

echo "==> Dumping schema and data for each table ..."
IFS=$'\n'
for t in $TABLES; do
  [ -z "$t" ] && continue

  curl -fsS "$CH_URL?query=$(printf %s "SHOW CREATE TABLE $CH_DB.$t FORMAT TSVRaw" | ue)" \
    | sed -e 's/\\n/\n/g' > "$WORKDIR/schema/$t.sql"

  curl -fsS --data-binary "SELECT * FROM $CH_DB.$t FORMAT Native" "$CH_URL" > "$WORKDIR/data/$t.native"
done
unset IFS

PLAIN_PATH="$NOMAD_TASK_DIR/plausible-clickhouse-$DATE.tar.gz"
ENC_PATH="$PLAIN_PATH.gpg"

echo "==> Packing dump directory ..."
tar -C "$WORKDIR" -czf "$PLAIN_PATH" .

REMOTE="gdrive:backups/plausible/clickhouse"

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
rm -rf "$WORKDIR" || true
rm -f "$ENC_PATH" || true

echo "==> ClickHouse backup finished."
SCRIPT
        ]

        volumes = [
          "/home/ayden/.config/rclone/rclone.conf:/local/rclone.conf:ro",
          "/home/ayden/.gnupg:/gnupg:ro",
        ]
      }

      resources {
        cpu    = 250
        memory = 256
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
CLICKHOUSE_DB=plausible_events_db

GPG_RECIPIENT={{ key "backup/gpg/key" }}
RETENTION_DAYS={{ key "backup/retention/days" }}
EOH
      }

      template {
        destination = "local/ch.env"
        env         = true
        data        = <<EOH
{{- $svc := service "plausible-clickhouse" -}}
{{- if gt (len $svc) 0 -}}
CH_HOST={{ (index $svc 0).Address }}
CH_PORT={{ (index $svc 0).Port }}
{{- end -}}
EOH
      }
    }
  }
}
