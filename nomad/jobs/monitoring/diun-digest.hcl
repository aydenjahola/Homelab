job "diun-digest" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 9 * * 1"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "digest" {
    count = 1

    max_run_duration = "10m"

    restart {
      attempts = 0
      mode     = "fail"
    }

    reschedule {
      attempts  = 0
      unlimited = false
    }

    task "digest" {
      driver = "docker"

      config {
        image   = "alpine:3.24.4"
        command = "/bin/sh"
        args = [
          "-c",
          <<SCRIPT
set -eu
apk add --no-cache curl >/dev/null

: "$NTFY_URL"
: "$NTFY_TOKEN"

[ -s /data/pending.tsv ] || { echo "no updates queued"; exit 0; }
mv /data/pending.tsv /data/sending.tsv

sort -u /data/sending.tsv | awk -F '\t' '{ if ($2 != "") printf "- [%s](%s)\n", $1, $2; else printf "- %s\n", $1 }' > /local/body.md
count="$(wc -l < /local/body.md | tr -d ' ')"

curl -fsS -H @"$NOMAD_SECRETS_DIR/ntfy-auth" \
  -H "Title: $count image updates this week" -H "Priority: 2" -H "Tags: package" -H "Markdown: yes" \
  --data-binary @/local/body.md "$NTFY_URL/homelab-updates" >/dev/null

rm -f /data/sending.tsv
cat /local/body.md
SCRIPT
        ]

        volumes = [
          "/storage/nomad/diun/diun:/data:rw",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
NTFY_URL   = {{ key "ntfy/url" }}
NTFY_TOKEN = {{ key "ntfy/token/diun" }}
EOH
      }

      template {
        destination          = "secrets/ntfy-auth"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
Authorization: Bearer {{ key "ntfy/token/diun" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 128
      }
    }
  }
}
