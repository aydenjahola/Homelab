# Pull-based continuous deployment for this repo.
#
# Every INTERVAL seconds:
#   1. renovate/* branches whose PR was closed: put their jobs back to the main version.
#   2. main moved since the last deployed SHA (kept in Consul): deploy the changed job files.
#   3. renovate/* branches with a new head SHA and green CI: deploy their changed job files,
#      wait for health, post a "deploy" commit status. On failure, revert to the version
#      that ran before and post a failing status, which blocks Renovate's automerge.
#
# State: Consul KV under deployer/ (main/sha, branch/<branch name>).
# One-shot batch jobs, parameterized jobs and this job itself are never deployed.
job "deployer" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    repository = "aydenjahola/Homelab"
    interval   = "180"
  }

  group "deployer" {
    count = 1

    restart {
      attempts = 3
      interval = "30m"
      delay    = "1m"
      mode     = "delay"
    }

    # The nomad binary is glibc-linked, so it is copied out of the official
    # image and run on Debian (not Alpine)
    task "nomad-cli" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image        = "hashicorp/nomad:2.0.3"
        entrypoint   = ["/bin/sh"]
        args         = ["-c", "cp /bin/nomad /alloc/data/nomad && chmod 0755 /alloc/data/nomad"]
        security_opt = ["no-new-privileges:true"]
      }

      # Copying the ~150 MB binary fills page cache, which counts against the limit
      resources {
        cpu        = 50
        memory     = 64
        memory_max = 512
      }
    }

    task "deployer" {
      driver = "docker"

      config {
        image        = "debian:13.7-slim"
        command      = "/bin/sh"
        security_opt = ["no-new-privileges:true"]
        args = [
          "-c",
          <<SCRIPT
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl git jq >/dev/null
export PATH="/alloc/data:$PATH"
nomad version

: "$REPO"
: "$INTERVAL"
: "$GH_TOKEN"
: "$NOMAD_ADDR"
: "$CONSUL_ADDR"
: "$NOMAD_UI"
: "$DISCORD_WEBHOOK_URL"

OWNER="$(echo "$REPO" | cut -d/ -f1)"
KV="$CONSUL_ADDR/v1/kv/deployer"
SRC=/local/repo
SELF=deployer

log() { echo "$(date '+%F %T') $*"; }

ghapi() {
  # ghapi METHOD PATH [JSON]
  if [ $# -ge 3 ]; then
    curl -fsS -X "$1" -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com$2" -d "$3"
  else
    curl -fsS -X "$1" -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com$2"
  fi
}

kv_get()  { curl -fsS "$KV/$1?raw" 2>/dev/null || true; }
kv_put()  { curl -fsS -X PUT --data-binary "$2" "$KV/$1" >/dev/null; }
kv_del()  { curl -fsS -X DELETE "$KV/$1" >/dev/null; }
kv_keys() { curl -fsS "$KV/$1?keys" 2>/dev/null | jq -r '.[]' || true; }

branch_state() {
  # branch_state SHA STATUS FILES...
  s="$1"; st="$2"; shift 2
  printf '%s\n' "$@" | grep -v '^$' | jq -R . | jq -sc --arg s "$s" --arg st "$st" '{sha: $s, status: $st, files: .}'
}

notify() {
  jq -n --arg c "$1" '{content: $c, allowed_mentions: {users: ["367293674981294086"]}}' \
    | curl -sS -H "Content-Type: application/json" -d @- "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

set_status() {
  # set_status SHA STATE DESCRIPTION
  body="$(jq -n --arg s "$2" --arg d "$(printf '%s' "$3" | cut -c1-140)" --arg u "$NOMAD_UI" \
    '{state: $s, context: "deploy", description: $d, target_url: $u}')"
  ghapi POST "/repos/$REPO/statuses/$1" "$body" >/dev/null || log "!! could not set status on $1"
}

ci_state() {
  # pending | success | failure, from the check runs on a commit
  runs="$(ghapi GET "/repos/$REPO/commits/$1/check-runs?per_page=100")" || { echo pending; return 0; }
  echo "$runs" | jq -r '
    if .total_count == 0 then "pending"
    elif any(.check_runs[]; .status != "completed") then "pending"
    elif all(.check_runs[]; .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral") then "success"
    else "failure" end'
}

pr_state() {
  # none | open | closed, for the PRs whose head is the given branch
  prs="$(ghapi GET "/repos/$REPO/pulls?state=all&head=$OWNER:$1")" || { echo unknown; return 0; }
  echo "$prs" | jq -r 'if length == 0 then "none" elif any(.[]; .state == "open") then "open" else "closed" end'
}

changed_jobs() {
  # changed_jobs RANGE: added or modified job files
  git -C "$SRC" diff --name-only --diff-filter=AM "$1" -- nomad/jobs | grep '\.hcl$' || true
}

job_version() { curl -fsS "$NOMAD_ADDR/v1/job/$1" 2>/dev/null | jq -r '.Version' || true; }

wait_healthy() {
  # wait_healthy ID VERSION TYPE; reason for a failure goes to /local/reason
  id="$1"; v="$2"; type="$3"
  : > /local/reason
  case "$type" in batch|sysbatch) return 0 ;; esac

  if [ "$type" = service ]; then
    i=0
    while [ "$i" -lt 180 ]; do
      d="$(curl -fsS "$NOMAD_ADDR/v1/job/$id/deployment" 2>/dev/null || echo null)"
      st="$(echo "$d" | jq -r --argjson v "$v" 'if . != null and .JobVersion == $v then .Status else "" end')"
      case "$st" in
        successful) return 0 ;;
        failed|cancelled)
          echo "$d" | jq -r '.StatusDescription' > /local/reason
          return 1 ;;
        "")
          # No deployment for this version after 90s: fall back to allocation checks
          [ "$i" -ge 9 ] && break ;;
      esac
      i=$((i + 1))
      sleep 10
    done
    if [ "$i" -ge 180 ]; then
      echo "deployment still running after 30m" > /local/reason
      return 1
    fi
  fi

  i=0
  ok=0
  while [ "$i" -lt 60 ]; do
    a="$(curl -fsS "$NOMAD_ADDR/v1/job/$id/allocations" 2>/dev/null || echo '[]')"
    s="$(echo "$a" | jq -r --argjson v "$v" '
      [.[] | select(.JobVersion == $v and .DesiredStatus == "run")]
      | if length == 0 then "pending"
        elif any(.[]; .ClientStatus == "failed") then "failed"
        elif all(.[]; .ClientStatus == "running") then "running"
        else "pending" end')"
    case "$s" in
      failed)
        echo "allocation failed" > /local/reason
        return 1 ;;
      running)
        ok=$((ok + 1))
        [ "$ok" -ge 3 ] && return 0 ;;
      *) ok=0 ;;
    esac
    i=$((i + 1))
    sleep 10
  done
  echo "allocations not running after 10m" > /local/reason
  return 1
}

deploy_one() {
  # deploy_one GIT_REF PATH; prints one result line, returns non-zero on failure
  ref="$1"; path="$2"

  # Parse locally from a checkout of nomad/ at this ref, like CI does: the
  # server-side parse endpoint disables file(), which some jobs use
  rm -rf /local/tree
  mkdir -p /local/tree
  if ! git -C "$SRC" archive "$ref" nomad | tar -x -C /local/tree; then
    echo "$path: checkout of $ref failed"
    return 1
  fi
  if [ ! -f "/local/tree/$path" ]; then
    echo "$path: not on $ref, skipped"
    return 0
  fi
  cp "/local/tree/$path" /local/job.hcl

  rel="$(echo "$path" | sed 's#^nomad/##')"
  if ! (cd /local/tree/nomad && nomad job run -output "$rel") > /local/job.out 2> /local/err; then
    echo "$path: parse failed: $(head -c 200 /local/err | tr '\n' ' ')"
    return 1
  fi
  jq '.Job' /local/job.out > /local/job.json

  id="$(jq -r '.ID' /local/job.json)"
  type="$(jq -r '.Type' /local/job.json)"
  oneshot="$(jq -r '((.Type == "batch" or .Type == "sysbatch") and .Periodic == null) or .ParameterizedJob != null' /local/job.json)"

  if [ "$oneshot" = true ]; then
    echo "$id: one-shot job, skipped"
    return 0
  fi
  if [ "$id" = "$SELF" ]; then
    echo "$id: never redeploys itself, skipped"
    return 0
  fi

  before="$(job_version "$id")"
  jq -n --slurpfile j /local/job.json --rawfile h /local/job.hcl \
    '{Job: $j[0], Submission: {Source: $h, Format: "hcl2"}}' > /local/register.json
  if ! curl -sS --fail-with-body -X POST -d @/local/register.json "$NOMAD_ADDR/v1/jobs" > /local/err 2>&1; then
    echo "$id: register failed: $(head -c 200 /local/err | tr '\n' ' ')"
    return 1
  fi
  after="$(job_version "$id")"

  if [ "$before" = "$after" ]; then
    echo "$id: unchanged"
    return 0
  fi
  if wait_healthy "$id" "$after" "$type"; then
    echo "$id: healthy at v$after"
    return 0
  fi

  reason="$(cat /local/reason)"
  if [ -n "$before" ]; then
    if jq -n --arg id "$id" --argjson v "$before" '{JobID: $id, JobVersion: $v}' \
        | curl -sS --fail-with-body -X POST -d @- "$NOMAD_ADDR/v1/job/$id/revert" > /local/err 2>&1; then
      echo "$id: failed ($reason), reverted to v$before"
    else
      echo "$id: failed ($reason), revert to v$before: $(head -c 120 /local/err | tr '\n' ' ')"
    fi
  else
    echo "$id: failed ($reason), new job left in place"
  fi
  return 1
}

deploy_files() {
  # deploy_files GIT_REF FILES...; sets RESULT and returns non-zero if any job failed
  ref="$1"; shift
  RESULT=""
  failed=0
  for f in "$@"; do
    if line="$(deploy_one "$ref" "$f")"; then :; else failed=1; fi
    log "   $line"
    RESULT="$RESULT$line; "
  done
  return "$failed"
}

finish_branches() {
  # Branches whose PR closed (merged or not), or that were deleted: jobs go back to main
  for key in $(kv_keys branch/); do
    b="$(echo "$key" | sed 's#^deployer/branch/##')"
    state="$(kv_get "branch/$b")"
    status="$(echo "$state" | jq -r '.status // "active"')"

    if git -C "$SRC" show-ref --verify --quiet "refs/remotes/origin/$b"; then
      [ "$status" = "done" ] && continue
      [ "$(pr_state "$b")" = closed ] || continue
      gone=0
    else
      gone=1
    fi

    if [ "$status" != "done" ]; then
      # shellcheck disable=SC2046
      set -- $(echo "$state" | jq -r '.files[]')
      if [ $# -gt 0 ]; then
        log "$b: finished, putting its jobs back on main"
        deploy_files origin/main "$@" || notify "❌ <@367293674981294086> **deployer**: restoring main after \`$b\` closed: $RESULT"
      fi
    fi

    if [ "$gone" -eq 1 ]; then
      kv_del "branch/$b"
    else
      kv_put "branch/$b" "$(echo "$state" | jq -c '.status = "done"')"
    fi
  done
}

deploy_main() {
  main="$(git -C "$SRC" rev-parse origin/main)"
  last="$(kv_get main/sha)"

  if [ -z "$last" ]; then
    kv_put main/sha "$main"
    log "main: first run, recorded $main as deployed, nothing deployed"
    return 0
  fi
  [ "$last" = "$main" ] && return 0

  case "$(ci_state "$main")" in
    pending)
      log "main: $main waiting for CI"
      return 0 ;;
    failure)
      # Keep main/sha where it is: once a later commit fixes CI, every job
      # changed since the last good deploy goes out together. Alert once per commit.
      if [ "$(kv_get main/failed)" != "$main" ]; then
        set_status "$main" failure "CI failed, not deployed"
        notify "❌ <@367293674981294086> **deployer**: CI failed on main \`$main\`, not deployed. The cluster stays on \`$last\` until CI passes."
        kv_put main/failed "$main"
      fi
      return 0 ;;
  esac

  if ! git -C "$SRC" cat-file -e "$last^{commit}" 2>/dev/null; then
    notify "⚠️ <@367293674981294086> **deployer**: last deployed commit \`$last\` is no longer in history. Recorded \`$main\` without deploying; check the cluster by hand."
    kv_put main/sha "$main"
    return 0
  fi

  # shellcheck disable=SC2046
  set -- $(changed_jobs "$last..$main")
  if [ $# -eq 0 ]; then
    kv_put main/sha "$main"
    return 0
  fi

  log "main: $last..$main changes $# job file(s)"
  set_status "$main" pending "Deploying to the cluster"
  if deploy_files origin/main "$@"; then
    set_status "$main" success "$RESULT"
  else
    set_status "$main" failure "$RESULT"
    notify "❌ <@367293674981294086> **deployer**: deploying main \`$main\` failed: $RESULT"
  fi
  kv_put main/sha "$main"
}

deploy_branches() {
  for b in $(git -C "$SRC" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/renovate/); do
    sha="$(git -C "$SRC" rev-parse "origin/$b")"
    state="$(kv_get "branch/$b")"
    if [ -n "$state" ] && [ "$(echo "$state" | jq -r '.sha')" = "$sha" ]; then
      continue
    fi

    case "$(pr_state "$b")" in
      closed)
        kv_put "branch/$b" "$(branch_state "$sha" "done")"
        continue ;;
      unknown) continue ;;
    esac

    case "$(ci_state "$sha")" in
      pending)
        log "$b: waiting for CI on $sha"
        continue ;;
      failure)
        set_status "$sha" failure "CI failed, not deployed"
        kv_put "branch/$b" "$(branch_state "$sha" active)"
        continue ;;
    esac

    # shellcheck disable=SC2046
    set -- $(changed_jobs "origin/main...$sha")
    if [ $# -eq 0 ]; then
      set_status "$sha" success "No Nomad job changes"
      kv_put "branch/$b" "$(branch_state "$sha" active)"
      continue
    fi

    # Deploy the branch merged onto current main, so a branch that is behind
    # never rolls back newer main changes to the same file
    if ! merged="$(git -C "$SRC" merge-tree --write-tree origin/main "$sha" 2>/dev/null)"; then
      set_status "$sha" failure "Conflicts with main, not deployed"
      kv_put "branch/$b" "$(branch_state "$sha" active)"
      continue
    fi
    tree="$(echo "$merged" | head -n 1)"

    log "$b: deploying $sha ($# job file(s))"
    set_status "$sha" pending "Deploying to the cluster"
    if deploy_files "$tree" "$@"; then
      set_status "$sha" success "$RESULT"
    else
      failure="$RESULT"
      # Put every job this branch touched back on main, not only the one that failed
      deploy_files origin/main "$@" || true
      set_status "$sha" failure "$failure"
      notify "❌ <@367293674981294086> **deployer**: \`$b\` failed and was rolled back to main: $failure"
    fi
    kv_put "branch/$b" "$(branch_state "$sha" active "$@")"
  done
}

mark_other_prs() {
  # "deploy" is a required check, but only renovate/* branches are deployed
  # before merge. Other same-repo PRs get a success status saying so.
  prs="$(ghapi GET "/repos/$REPO/pulls?state=open&per_page=100")" || return 0
  echo "$prs" | jq -r --arg r "$REPO" \
    '.[] | select(.head.repo.full_name == $r and (.head.ref | startswith("renovate/") | not)) | .head.sha' \
    | while read -r sha; do
      [ -n "$sha" ] || continue
      has="$(ghapi GET "/repos/$REPO/commits/$sha/status" | jq -r '[.statuses[] | select(.context == "deploy")] | length')" || continue
      if [ "$has" = 0 ]; then
        set_status "$sha" success "Not deployed before merge; deploys from main after merge"
      fi
    done
}

run_once() {
  # set -e does not apply here (called from an if), so check each step
  git -C "$SRC" fetch --quiet --prune origin || return 1
  finish_branches
  deploy_main
  deploy_branches
  mark_other_prs
}

if [ ! -d "$SRC/.git" ]; then
  git clone --quiet "https://github.com/$REPO.git" "$SRC"
fi

log "deployer started for $REPO, every $INTERVAL s"
while true; do
  if ! (run_once); then
    log "!! run failed"
  fi
  sleep "$INTERVAL"
done
SCRIPT
        ]
      }

      env = {
        "TZ"          = "Europe/Dublin"
        "REPO"        = "${NOMAD_META_repository}"
        "INTERVAL"    = "${NOMAD_META_interval}"
        "NOMAD_ADDR"  = "http://${attr.unique.network.ip-address}:4646"
        "NOMAD_UI"    = "http://${attr.unique.network.ip-address}:4646/ui/jobs"
        "CONSUL_ADDR" = "http://${attr.unique.network.ip-address}:8500"
      }

      # Shares Renovate's PAT. Needs Commit statuses read/write, Pull requests read, Checks read, Contents read.
      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
GH_TOKEN            = {{ key "renovate/github/token" }}
DISCORD_WEBHOOK_URL = {{ key "deployer/discord/webhook" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 768
      }
    }
  }
}
