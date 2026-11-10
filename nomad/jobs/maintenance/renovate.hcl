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

    task "renovate" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image        = "renovate/renovate:44.224.2"
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
        "RENOVATE_GIT_AUTHOR"        = "Renovate Bot <renovate@local.aydenjahola.com>"
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
RENOVATE_TOKEN            = {{ key "renovate/github/token" }}
RENOVATE_GITHUB_COM_TOKEN = {{ key "renovate/github/token" }}
RENOVATE_HOST_RULES       = [{"matchHost":"docker.io","hostType":"docker","username":"{{ key "docker/hub/user" }}","password":"{{ key "docker/hub/token" }}"},{"matchHost":"ghcr.io","hostType":"docker","username":"{{ key "docker/ghcr/user" }}","password":"{{ key "docker/ghcr/token" }}"}]
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
