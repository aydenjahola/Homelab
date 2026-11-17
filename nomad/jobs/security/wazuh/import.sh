#!/bin/sh
# Imports the homelab dashboards and applies the ISM retention policy. Idempotent.
set -u
AUTH="admin:${ADMIN_PASSWORD}"
DASH="http://${NOMAD_ADDR_http}"
POLICY=wazuh-retention

tries=0
# The Wazuh app restarts the server once on first boot, so wait for two green checks.
green=0
until [ "$green" -ge 2 ]; do
  curl -fsS -u "$AUTH" "$DASH/api/status" 2>/dev/null | grep -q '"state":"green"' && green=$((green + 1)) || green=0
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then
    echo "dashboard API not ready after 10m, skipping import"
    exit 0
  fi
  sleep 10
done

# 00-* holds the index patterns the Wazuh app owns: create them if missing, never overwrite.
for f in /local/dashboards/*.ndjson; do
  name=$(basename "$f")
  case "$name" in 00-*) overwrite=false ;; *) overwrite=true ;; esac
  for attempt in 1 2 3 4 5 6; do
    out=$(curl -sS -u "$AUTH" -H 'osd-xsrf: true' -F "file=@$f" \
      "$DASH/api/saved_objects/_import?overwrite=$overwrite") && break
    sleep 20
  done
  echo "$name: $(echo "$out" | grep -o '"successCount":[0-9]*')"
  echo "$out" | grep -o '"error":{"type":"[a-z_]*"[^}]*}' | grep -v '"conflict"' || true
done

curl_idx() {
  curl -sS --cacert /secrets/root-ca.pem -u "$AUTH" -H 'Content-Type: application/json' "$@"
}

current=$(curl_idx "$INDEXER_URL/_plugins/_ism/policies/$POLICY")
seq_no=$(echo "$current" | grep -o '"_seq_no":[0-9]*' | cut -d: -f2)
term=$(echo "$current" | grep -o '"_primary_term":[0-9]*' | cut -d: -f2)
query=""
[ -n "$seq_no" ] && query="?if_seq_no=$seq_no&if_primary_term=$term"
echo "ism policy: $(curl_idx -X PUT "$INDEXER_URL/_plugins/_ism/policies/$POLICY$query" -d @/local/ism-retention.json | grep -o '"_version":[0-9]*\|"error".*')"
echo "ism attach: $(curl_idx -X POST "$INDEXER_URL/_plugins/_ism/add/wazuh-alerts-*,wazuh-archives-*" -d "{\"policy_id\":\"$POLICY\"}" | grep -o '"updated_indices":[0-9]*')"
