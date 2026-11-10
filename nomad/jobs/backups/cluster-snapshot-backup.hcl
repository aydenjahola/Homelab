job "cluster-snapshot-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["30 3 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "backup" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay    = "30s"
      mode     = "fail"
    }

    task "consul-snapshot" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image      = "hashicorp/consul:2.1.0"
        entrypoint = ["/bin/sh"]
        args = [
          "-c",
          <<SCRIPT
set -eu
echo "==> consul snapshot save from $CONSUL_HTTP_ADDR ..."
if ! consul snapshot save "$NOMAD_ALLOC_DIR/data/consul.snap"; then
  wget -q -O /dev/null --header "Content-Type: application/json" \
    --post-data "{\"content\":\"❌ <@367293674981294086> **cluster-snapshot-backup** consul snapshot failed on $(hostname). Check Nomad alloc logs.\",\"allowed_mentions\":{\"users\":[\"367293674981294086\"]}}" \
    "$DISCORD_WEBHOOK_URL" || true
  exit 1
fi
consul snapshot inspect "$NOMAD_ALLOC_DIR/data/consul.snap" >/dev/null
SCRIPT
        ]
      }

      env {
        TZ               = "Europe/Dublin"
        CONSUL_HTTP_ADDR = "http://${attr.unique.network.ip-address}:8500"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
DISCORD_WEBHOOK_URL = {{ key "backup/webhook/discord" }}
EOH
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 256
      }
    }

    task "nomad-snapshot" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image      = "hashicorp/nomad:2.0.3"
        entrypoint = ["/bin/sh"]
        args = [
          "-c",
          <<SCRIPT
set -eu
echo "==> nomad operator snapshot save from $NOMAD_ADDR ..."
if ! nomad operator snapshot save "$NOMAD_ALLOC_DIR/data/nomad.snap"; then
  wget -q -O /dev/null --header "Content-Type: application/json" \
    --post-data "{\"content\":\"❌ <@367293674981294086> **cluster-snapshot-backup** nomad snapshot failed on $(hostname). Check Nomad alloc logs.\",\"allowed_mentions\":{\"users\":[\"367293674981294086\"]}}" \
    "$DISCORD_WEBHOOK_URL" || true
  exit 1
fi
nomad operator snapshot inspect "$NOMAD_ALLOC_DIR/data/nomad.snap" >/dev/null
SCRIPT
        ]
      }

      env {
        TZ         = "Europe/Dublin"
        NOMAD_ADDR = "http://${attr.unique.network.ip-address}:4646"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
DISCORD_WEBHOOK_URL = {{ key "backup/webhook/discord" }}
EOH
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 256
      }
    }

    task "encrypt-snapshots" {
      driver = "docker"

      config {
        image   = "alpine:3.24.3"
        command = "/bin/sh"
        args = [
          "-lc",
          <<SCRIPT
set -euo pipefail

echo "==> Installing curl + gnupg + rclone + tzdata ..."
apk add --no-cache curl gnupg rclone tzdata ca-certificates >/dev/null

: "$GPG_FINGERPRINT"
: "$RETENTION_DAYS"
: "$DISCORD_WEBHOOK_URL"

export RCLONE_CONFIG="/local/rclone.conf"
REMOTE="gdrive:backups/cluster-snapshots"
DATA="$NOMAD_ALLOC_DIR/data"
DEST="/backup"

notify_ok() {
  curl -sS -H "Content-Type: application/json" \
    -d "$(printf '{"content":"%s"}' "$*")" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

notify_fail() {
  curl -sS -H "Content-Type: application/json" \
    -d "$(printf '{"content":"%s","allowed_mentions":{"users":["367293674981294086"]}}' "$*")" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

cleanup() {
  shred -u -z "$DATA/consul.snap" "$DATA/nomad.snap" 2>/dev/null || rm -f "$DATA/consul.snap" "$DATA/nomad.snap"
  rm -f "$DEST"/consul/.tmp-* "$DEST"/nomad/.tmp-* 2>/dev/null || true
}
trap cleanup EXIT
trap 'notify_fail "❌ <@367293674981294086> **cluster-snapshot-backup** failed on $(hostname) at $(date +%Y-%m-%dT%H:%M:%S%z). Check Nomad alloc logs."' ERR

export GNUPGHOME="$NOMAD_TASK_DIR/gnupg"
mkdir -p "$GNUPGHOME" "$DEST/consul" "$DEST/nomad"
chmod 700 "$GNUPGHOME"

echo "==> Verifying public key fingerprint ..."
FOUND="$(gpg --batch --with-colons --import-options show-only --import "$NOMAD_TASK_DIR/homelab-backup.asc" | awk -F: '/^fpr/ {print $10; exit}')"
if [ "$FOUND" != "$GPG_FINGERPRINT" ]; then
  echo "ERROR: key fingerprint mismatch (got '$FOUND', want '$GPG_FINGERPRINT')" >&2
  exit 1
fi
gpg --batch --import "$NOMAD_TASK_DIR/homelab-backup.asc"

STAMP="$(date +'%Y%m%d-%H%M%S')"

for NAME in consul nomad; do
  [ -s "$DATA/$NAME.snap" ] || { echo "ERROR: missing snapshot $NAME.snap" >&2; exit 1; }
  OUT="$DEST/$NAME/$NAME-$STAMP.snap.gpg"
  echo "==> Encrypting $NAME snapshot -> $OUT ..."
  gpg --batch --yes --trust-model always --recipient "$GPG_FINGERPRINT" \
    --output "$DEST/$NAME/.tmp-$NAME-$STAMP.gpg" --encrypt "$DATA/$NAME.snap"
  [ -s "$DEST/$NAME/.tmp-$NAME-$STAMP.gpg" ]
  mv "$DEST/$NAME/.tmp-$NAME-$STAMP.gpg" "$OUT"
  echo "==> Uploading $OUT to $REMOTE ..."
  rclone copy --transfers=4 --checkers=8 --checksum "$OUT" "$REMOTE"
done

echo "==> Pruning backups older than $RETENTION_DAYS days ..."
find "$DEST/consul" "$DEST/nomad" -type f -name '*.snap.gpg' -mtime "+$RETENTION_DAYS" -print -delete || true

echo "==> Pruning remote backups older than $RETENTION_DAYS days ..."
AGE="$(printf '%sd' "$RETENTION_DAYS")"
rclone delete "$REMOTE" --min-age "$AGE" || true
rclone rmdirs "$REMOTE" --leave-root || true

echo "==> Backup finished."
notify_ok "✅ **cluster-snapshot-backup** finished on \`$(hostname)\` at \`$(date +%Y-%m-%dT%H:%M:%S%z)\`. Files: \`consul-$STAMP.snap.gpg\`, \`nomad-$STAMP.snap.gpg\`."
SCRIPT
        ]

        volumes = [
          "/storage/nomad/cluster-snapshot-backup:/backup:rw",
          "/home/ayden/.config/rclone/rclone.conf:/local/rclone.conf:ro",
        ]
      }

      env {
        TZ              = "Europe/Dublin"
        GPG_FINGERPRINT = "8C2ACE04A26EC08625EB0FF371DD90AE4AE92742"
      }

      template {
        destination          = "local/homelab-backup.asc"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = file("jobs/backups/keys/homelab-backup.asc")
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
RETENTION_DAYS      = {{ key "backup/retention/days" }}
DISCORD_WEBHOOK_URL = {{ key "backup/webhook/discord" }}
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
