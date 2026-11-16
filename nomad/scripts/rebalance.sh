#!/usr/bin/env bash
# Move service allocations off an overloaded node, one at a time, until it holds
# no more than its share. The scheduler (spread) picks where each replacement goes.
# Usage: NOMAD_ADDR=http://192.168.1.100:4646 nomad/scripts/rebalance.sh <node-name>
set -euo pipefail

node="${1:?usage: rebalance.sh <node-name>}"
: "${NOMAD_ADDR:?set NOMAD_ADDR}"

api() { curl -fsS "$NOMAD_ADDR/v1/$1"; }

running() {
  api "allocations?filter=$(jq -rn --arg f 'ClientStatus == "running"' '$f|@uri')" \
    | jq -c '[.[] | select(.JobType == "service")]'
}

pinned() {
  api "job/$1" | jq -e '[.Constraints[]?, .TaskGroups[].Constraints[]?] | any(.LTarget | test("unique.hostname"))' >/dev/null
}

settled() {
  api "job/$1/summary" | jq -e --arg g "$2" '.Summary[$g] | .Queued == 0 and .Starting == 0 and .Running > 0' >/dev/null
}

nodes="$(api nodes | jq '[.[] | select(.Status == "ready" and .SchedulingEligibility == "eligible")] | length')"
moved=0

# Databases first so apps restart once onto their new db address.
for id in $(running | jq -r --arg n "$node" '
    [.[] | select(.NodeName == $n)]
    | sort_by(if .TaskGroup == "db" then 0 elif .JobID == "authentik" then 2 else 1 end)
    | .[].ID'); do
  all="$(running)"
  here="$(jq --arg n "$node" '[.[] | select(.NodeName == $n)] | length' <<<"$all")"
  total="$(jq length <<<"$all")"
  share=$(( (total + nodes - 1) / nodes ))
  [ "$here" -le "$share" ] && { echo "$node holds $here of $total (share $share), done"; break; }

  alloc="$(api "allocation/$id")"
  job="$(jq -r .JobID <<<"$alloc")"
  group="$(jq -r .TaskGroup <<<"$alloc")"
  pinned "$job" && continue

  echo "==> $job/$group"
  nomad alloc stop -detach "$id" >/dev/null
  sleep 5
  for _ in $(seq 1 60); do settled "$job" "$group" && break; sleep 5; done
  settled "$job" "$group" || { echo "!! $job/$group did not settle, stopping"; exit 1; }
  moved=$((moved + 1))
done

echo "moved $moved allocations"
running | jq -r '.[].NodeName' | sort | uniq -c
