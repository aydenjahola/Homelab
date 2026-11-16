job "truenas-alerts" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/5 * * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "forward" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    reschedule {
      attempts  = 0
      unlimited = false
    }

    task "forward" {
      driver = "docker"

      config {
        image   = "alpine:3.24.4"
        command = "/bin/sh"
        args = [
          "-c",
          <<SCRIPT
set -eu
apk add --no-cache curl jq >/dev/null

: "$TRUENAS_URL"
: "$TRUENAS_HOST"
: "$TRUENAS_IP"
: "$TRUENAS_API_KEY"
: "$NTFY_URL"
: "$NTFY_TOKEN"

state=/data/active.txt
touch "$state"

curl -fsS --resolve "$TRUENAS_HOST:443:$TRUENAS_IP" -H "Authorization: Bearer $TRUENAS_API_KEY" "$TRUENAS_URL/api/v2.0/alert/list" \
  | jq -c '.[] | select((.dismissed | not) and (.level | IN("WARNING","ERROR","CRITICAL","ALERT","EMERGENCY")))' \
  > /local/alerts.jsonl

jq -r .uuid /local/alerts.jsonl | sort > /local/now.txt

send() {
  curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -H "Priority: $1" -H "Tags: $2" \
    -H "Title: $3" -H "Click: $TRUENAS_URL/ui/alerts" \
    --data-binary "$4" "$NTFY_URL/homelab-alerts" >/dev/null
}

while read -r alert; do
  uuid="$(printf '%s' "$alert" | jq -r .uuid)"
  grep -qx "$uuid" "$state" && continue
  level="$(printf '%s' "$alert" | jq -r .level)"
  text="$(printf '%s' "$alert" | jq -r '.formatted // .text')"
  case "$level" in
    WARNING) prio=3 ;;
    ERROR) prio=4 ;;
    *) prio=5 ;;
  esac
  send "$prio" "warning" "TrueNAS $level" "$text"
done < /local/alerts.jsonl

gone="$(comm -23 "$state" /local/now.txt | wc -l | tr -d ' ')"
if [ "$gone" -gt 0 ]; then
  send 2 "white_check_mark" "TrueNAS" "$gone alert(s) cleared"
fi

cp /local/now.txt "$state"
SCRIPT
        ]

        volumes = [
          "/storage/nomad/truenas-alerts:/data:rw",
        ]
      }

      env {
        TZ           = "Europe/Dublin"
        TRUENAS_HOST = "nas.local.aydenjahola.com"
        TRUENAS_IP   = "192.168.1.103"
        TRUENAS_URL  = "https://nas.local.aydenjahola.com"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
TRUENAS_API_KEY = {{ key "truenas/api/key" }}
NTFY_URL        = {{ key "ntfy/url" }}
NTFY_TOKEN      = {{ key "ntfy/token/truenas" }}
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
