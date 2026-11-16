job "backup-digest" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 8 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "digest" {
    count = 1

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
apk add --no-cache curl jq >/dev/null

: "$NOMAD_ADDR"
: "$LOKI_URL"
: "$NTFY_URL"
: "$NTFY_TOKEN"

loki() {
  curl -fsS -G "$LOKI_URL/loki/api/v1/query" --data-urlencode "query=$1" \
    | jq -c '[.data.result[] | {key: .metric.task, value: (.value[1] | tonumber)}] | from_entries'
}

curl -fsS "$NOMAD_ADDR/v1/jobs" \
  | jq -r '.[] | select(.Periodic and .ParentID == "" and (.ID | test("backup$")) and (.Stop | not)) | .ID' \
  | while read -r job; do
      curl -fsS "$NOMAD_ADDR/v1/job/$job" | jq -r '.TaskGroups[].Tasks[] | select(.Lifecycle == null) | .Name'
    done | sort > /local/tasks.txt

loki 'sum by (task) (count_over_time({task=~".+"} |~ "(?i)backup finished" [24h]))' > /local/ok.json
loki 'sum by (task) (count_over_time({task=~".+"} |= "==> Installing" [24h]))' > /local/runs.json

total=0
good=0
: > /local/problems.txt
while read -r task; do
  total=$((total + 1))
  ok="$(jq -r --arg t "$task" '.[$t] // 0' /local/ok.json)"
  runs="$(jq -r --arg t "$task" '.[$t] // 0' /local/runs.json)"
  if [ "$ok" -eq 0 ]; then
    echo "- ❌ \`$task\`: no successful run ($runs attempts)" >> /local/problems.txt
  elif [ "$ok" -lt "$runs" ]; then
    good=$((good + 1))
    echo "- ⚠️ \`$task\`: $ok of $runs attempts succeeded" >> /local/problems.txt
  else
    good=$((good + 1))
  fi
done < /local/tasks.txt

if [ -s /local/problems.txt ]; then
  priority=4
  tags="floppy_disk,warning"
  body="$(cat /local/problems.txt)"
else
  priority=2
  tags="floppy_disk"
  body="Every backup task finished in the last 24h."
fi

curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" \
  -H "Title: Backups: $good/$total OK" -H "Priority: $priority" -H "Tags: $tags" -H "Markdown: yes" \
  --data-binary "$body" "$NTFY_URL/homelab-backups" >/dev/null
echo "$good/$total OK"
cat /local/problems.txt
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
NTFY_URL   = {{ key "ntfy/url" }}
NTFY_TOKEN = {{ key "ntfy/token/backups" }}
{{ range service "loki" }}
LOKI_URL={{ printf "http://%s:%d" .Address .Port }}
{{ end }}
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
