#!/usr/bin/env bash
# List every Consul KV key referenced by the Nomad job specs and blueprints.
#
#   scripts/kv-check.sh            print table: job file -> keys
#   scripts/kv-check.sh --check    also verify each key NAME exists in Consul
#                                  (values are never read); exit 1 if any missing
#   scripts/kv-check.sh --markdown print the per-job key list as markdown rows
#
# keyOrDefault references are optional and reported as "(default)" but never
# counted as missing. Uses CONSUL_HTTP_ADDR for --check.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="list"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  --markdown) mode="markdown" ;;
  -h | --help)
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
esac

# Emit "file<TAB>kind<TAB>key" for every reference.
refs() {
  local f
  while IFS= read -r f; do
    grep -oE '\b(keyOrDefault|key)[[:space:]]+"[^"]+"' "$f" 2>/dev/null |
      sed -E 's/^(keyOrDefault|key)[[:space:]]+"([^"]+)"$/\1\t\2/' |
      sort -u |
      while IFS=$'\t' read -r kind key; do
        printf '%s\t%s\t%s\n' "${f#"$root"/}" "$kind" "$key"
      done
  done < <(find "$root/jobs" -type f \( -name '*.hcl' -o -name '*.yaml' -o -name '*.yml' \) | sort)
}

all_refs="$(refs)"

if [[ "$mode" == "markdown" ]]; then
  printf '%s\n' "$all_refs" | awk -F'\t' '
    $1 != prev { if (prev != "") print ""; print "### `" $1 "`"; print ""; prev = $1 }
    { print "- `" $3 "`" ($2 == "keyOrDefault" ? " (optional)" : "") }'
  exit 0
fi

printf '%-60s  %s\n' "JOB FILE" "KEYS"
printf '%-60s  %s\n' "--------" "----"
printf '%s\n' "$all_refs" | awk -F'\t' '
  { k = $3 ($2 == "keyOrDefault" ? " (default)" : "")
    keys[$1] = keys[$1] (keys[$1] == "" ? "" : "\n" sprintf("%-60s  ", "")) k
    if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } }
  END { for (i = 1; i <= n; i++) printf "%-60s  %s\n", order[i], keys[order[i]] }'

[[ "$mode" == "check" ]] || exit 0

if ! command -v consul >/dev/null 2>&1; then
  echo "consul CLI not found" >&2
  exit 2
fi

# One listing of all key names (no values) with an empty separator.
existing="$(consul kv get -keys -separator="" "")"

missing=0
echo
while IFS=$'\t' read -r kind key; do
  if ! grep -Fxq -- "$key" <<<"$existing"; then
    if [[ "$kind" == "key" ]]; then
      echo "MISSING: $key"
      missing=$((missing + 1))
    else
      echo "absent (has default): $key"
    fi
  fi
done < <(printf '%s\n' "$all_refs" | cut -f2,3 | sort -u)

if ((missing > 0)); then
  echo "$missing required key(s) missing from Consul" >&2
  exit 1
fi
echo "all referenced keys exist"
