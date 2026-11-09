job "oxide" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "oxide.local.aydenjahola.com"
  }

  group "oxide" {
    count = 1

    # Canary keeps the current allocation serving traffic while the new one
    # proves itself healthy, then promotes it (zero-downtime with count = 1).
    update {
      max_parallel      = 1
      canary            = 1
      auto_promote      = true
      min_healthy_time  = "30s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = false
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

    shutdown_delay = "15s"

    network {
      mode = "bridge"

      port "dashboard" {
        to = 8080
      }

      # Serves generated AI DJ voice clips back to the oxide-lavalink task in
      # the separate oxide-data job. See AI_DJ_CLIP_BIND/PUBLIC_URL below.
      port "aidj_clip" {
        to = 8091
      }
    }

    service {
      name = "oxide-dashboard"
      port = "dashboard"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.oxide-dashboard.entrypoints=https",
        "traefik.http.routers.oxide-dashboard.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.oxide-dashboard.tls=true",
      ]

      check {
        name     = "oxide-dashboard-ready"
        type     = "http"
        path     = "/healthz"
        interval = "15s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "300s"
          ignore_warnings = false
        }
      }
    }

    service {
      name = "oxide-aidj-clip"
      port = "aidj_clip"

      check {
        name     = "oxide-aidj-clip-ready"
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "300s"
          ignore_warnings = false
        }
      }
    }

    task "oxide" {
      driver = "docker"

      kill_timeout = "20s"

      config {
        image      = "ghcr.io/aydenjahola/oxide:1.1.1"
        ports      = ["dashboard", "aidj_clip"]
        force_pull = true

        auth {
          username = "${DOCKER_USER}"
          password = "${DOCKER_PASS}"
        }
      }

      env {
        TZ       = "Europe/Dublin"
        RUST_LOG = "oxide=info,songbird=info"
      }

      template {
        destination          = "secrets/oxide.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
DOCKER_USER = {{ key "docker/ghcr/user" }}
DOCKER_PASS = {{ key "docker/ghcr/token" }}

DISCORD_TOKEN = {{ key "oxide/discord/token" }}
DATABASE_URL  = postgres://{{ key "oxide/postgres/user" }}:{{ key "oxide/postgres/password" }}@{{ range service "oxide-postgres" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "oxide/postgres/db" }}

LAVALINK_PASSWORD = {{ key "oxide/lavalink/password" }}
LAVALINK_URL      = http://{{ range service "oxide-lavalink" }}{{ .Address }}:{{ .Port }}{{ end }}

SPOTIFY_CLIENT_ID     = {{ key "oxide/spotify/client_id" }}
SPOTIFY_CLIENT_SECRET = {{ key "oxide/spotify/client_secret" }}

# AI DJ voice host: local, CPU-only LLM (oxide-llama-cpp task in
# oxide-data.hcl) plus the Piper voice baked into the image. Completely
# free, no API keys. AI_DJ_CLIP_PUBLIC_URL self-advertises this specific
# allocation's dynamic port so oxide-lavalink can fetch generated clips
# back from it. Toggle per server with /aidj.
LOCAL_LLM_URL          = http://{{ range service "oxide-llama-cpp" }}{{ .Address }}:{{ .Port }}{{ end }}
PIPER_VOICE_MODEL_PATH = /opt/piper-voices/en_US-lessac-medium.onnx
AI_DJ_CLIP_BIND        = 0.0.0.0:8091
AI_DJ_CLIP_PUBLIC_URL  = http://{{ env "NOMAD_ADDR_aidj_clip" }}

# Optional, free tempo lookups that sharpen smooth transitions; fades still
# work with no key set. Add oxide/getsongbpm/api_key to Consul KV to enable.
GETSONGBPM_API_KEY = {{ keyOrDefault "oxide/getsongbpm/api_key" "" }}

# Executables must be available on PATH unless overridden
YTDLP_BIN = yt-dlp
RUST_LOG  = oxide=info,songbird=info

# Bot appearance and behavior
BOT_NAME                         = Oxide
BOT_COLOR                        = 5865F2
BOT_STATUS                       = online
BOT_ACTIVITY_TYPE                = listening
BOT_ACTIVITY                     = /help
DEFAULT_VOLUME                   = 1.0
QUEUE_DISPLAY_LIMIT              = 10
AUTO_JOIN                        = true
MAX_QUEUE_SIZE                   = 250
COMMAND_COOLDOWN_SECONDS         = 3
MAX_CONCURRENT_RESOLVERS         = 4
SPOTIFY_RESOLVE_CONCURRENCY      = 4
AUTOPLAY_BATCH_SIZE              = 3
AUTOPLAY_SEED_LIMIT              = 3
AUTOPLAY_HISTORY_LIMIT           = 20
LAVALINK_HEALTH_INTERVAL_SECONDS = 15
LAVALINK_FAILURE_THRESHOLD       = 2
EXTERNAL_HTTP_TIMEOUT_SECONDS    = 20
EXTERNAL_HTTP_RETRIES            = 2
EXTERNAL_RESPONSE_MAX_BYTES      = 2097152
EXTERNAL_CACHE_TTL_SECONDS       = 21600
QUEUE_PERSIST_DEBOUNCE_MS        = 250
OBSERVABILITY_RETENTION_DAYS     = 30
GRACEFUL_SHUTDOWN_SECONDS        = 15

# Leave an empty voice channel after this many seconds; 0 disables it
IDLE_DISCONNECT_SECONDS = 300
# Rejoin remembered voice channels and continue persisted queues after restart
RESUME_PLAYBACK_ON_START = true

# Optional Discord-authenticated admin dashboard
# Add DASHBOARD_PUBLIC_URL/auth/callback as an OAuth2 redirect in the Discord Developer Portal.
DASHBOARD_BIND                = 0.0.0.0:8080
DASHBOARD_PUBLIC_URL          = https://{{ env "NOMAD_META_domain" }}
DISCORD_CLIENT_ID             = {{ key "oxide/discord/client_id" }}
DISCORD_CLIENT_SECRET         = {{ key "oxide/discord/client_secret" }}
# Discord user ID for the bot owner; grants full dashboard visibility and control
DASHBOARD_SUPER_ADMIN_USER_ID = {{ key "oxide/discord/super_admin_user_id" }}
# Optional legacy bearer access to the read-only status API (minimum 16 characters)

# Optional: register commands instantly in one development server
# COMMAND_GUILD_ID=123456789012345678

# Resolve upcoming Lavalink tracks ahead of time so track transitions have
# no network round-trip on the critical path. 0 disables prefetching.
PREFETCH_LOOKAHEAD   = 2
PREFETCH_TTL_SECONDS = 600
EOH
      }

      resources {
        cpu        = 1000
        memory     = 64
        memory_max = 2048
      }

      restart {
        attempts = 10
        interval = "10m"
        delay    = "15s"
        mode     = "delay"
      }
    }
  }
}
