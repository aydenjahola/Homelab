job "renovate" {
  datacenters = ["dc1"]
  type        = "batch"

  meta {
    repository = "aydenjahola/Homelab"
  }

  # Policy lives in /renovate.json in the repo; this job only runs the bot.
  periodic {
    crons            = ["17 */2 * * *"]
    prohibit_overlap = true
    time_zone        = "Europe/Dublin"
  }

  group "renovate" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    reschedule {
      attempts  = 0
      unlimited = false
    }

    # Mints a GitHub App installation token for this run (valid 1 hour). Renovate
    # acts as the app, not as the repo admin, so the main ruleset's required
    # checks (including "deploy") are enforced on its merges.
    task "github-app-token" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image        = "alpine:3.24.3"
        command      = "/bin/sh"
        security_opt = ["no-new-privileges:true"]
        args = [
          "-c",
          <<SCRIPT
set -eu

apk add --no-cache curl jq openssl >/dev/null

: "$APP_ID"
: "$REPO"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

need() {
  # need NAME VALUE: stop before Renovate runs with an empty value
  if [ -z "$2" ] || [ "$2" = null ]; then
    echo "!! could not get $1 (is the app installed on $REPO?)" >&2
    exit 1
  fi
}

gh() {
  # gh TOKEN [curl args...]
  t="$1"; shift
  curl -fsS -H "Authorization: Bearer $t" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

now="$(date +%s)"
header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$APP_ID" | b64url)"
sig="$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign /secrets/app.pem | b64url)"
jwt="$header.$payload.$sig"

installation="$(gh "$jwt" "https://api.github.com/repos/$REPO/installation" | jq -r '.id')"
need "installation id" "$installation"
token="$(gh "$jwt" -X POST "https://api.github.com/app/installations/$installation/access_tokens" | jq -r '.token')"
need "installation token" "$token"
slug="$(gh "$jwt" "https://api.github.com/app" | jq -r '.slug')"
need "app slug" "$slug"
bot="$slug"'[bot]'
bot_id="$(curl -fsS "https://api.github.com/users/$slug%5Bbot%5D" | jq -r '.id')"
need "bot user id" "$bot_id"

umask 077
cat > /alloc/data/renovate.env <<EOF
RENOVATE_TOKEN='$token'
RENOVATE_GITHUB_COM_TOKEN='$token'
RENOVATE_USERNAME='$bot'
RENOVATE_GIT_AUTHOR='$bot <$bot_id+$bot@users.noreply.github.com>'
EOF
chown 1000:1000 /alloc/data/renovate.env
echo "==> token minted for $bot (installation $installation)"
SCRIPT
        ]
      }

      env = {
        "REPO" = "${NOMAD_META_repository}"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
APP_ID = {{ key "renovate/github-app/id" }}
EOH
      }

      template {
        destination          = "secrets/app.pem"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
{{ key "renovate/github-app/private-key" }}
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "renovate" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image = "renovate/renovate:44.224.2"
        # Keep the image entrypoint; load the app token minted by the prestart task
        command      = "sh"
        args         = ["-c", "set -a && . /alloc/data/renovate.env && set +a && exec renovate"]
        security_opt = ["no-new-privileges:true"]
        cap_drop     = ["all"]

        # Literal path: a periodic child's NOMAD_JOB_NAME includes /periodic-<id>
        volumes = [
          "/storage/nomad/renovate/cache:/cache:rw",
        ]
      }

      env = {
        "TZ"                         = "Europe/Dublin"
        "HOME"                       = "/cache/home"
        "LOG_LEVEL"                  = "info"
        "RENOVATE_PLATFORM"          = "github"
        "RENOVATE_REPOSITORIES"      = "${NOMAD_META_repository}"
        "RENOVATE_ONBOARDING"        = "false"
        "RENOVATE_REQUIRE_CONFIG"    = "required"
        "RENOVATE_BASE_DIR"          = "/cache/base"
        "RENOVATE_CACHE_DIR"         = "/cache/cache"
        "RENOVATE_REPOSITORY_CACHE"  = "enabled"
        "RENOVATE_PERSIST_REPO_DATA" = "true"
        "RENOVATE_BINARY_SOURCE"     = "global"
      }

      # Docker Hub / GHCR creds avoid anonymous rate limits on tag lookups.
      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
RENOVATE_HOST_RULES =  [{"matchHost":"docker.io","hostType":"docker","username":"{{ key "docker/hub/user" }}","password":"{{ key "docker/hub/token" }}"},{"matchHost":"ghcr.io","hostType":"docker","username":"{{ key "docker/ghcr/user" }}","password":"{{ key "docker/ghcr/token" }}"}]
EOH
      }

      resources {
        cpu        = 500
        memory     = 512
        memory_max = 2048
      }
    }
  }
}
