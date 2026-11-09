job "oxide-data" {
  datacenters = ["dc1"]
  type        = "service"

  group "data" {
    count = 1

    shutdown_delay = "15s"

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
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

    network {
      mode = "bridge"

      port "postgres" {
        to = 5432
      }

      port "lavalink" {
        to = 2333
      }

      port "llama_cpp" {
        to = 8080
      }
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["postgres"]

        volumes = [
          "/storage/nomad/oxide/postgres:/var/lib/postgresql/data",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      service {
        name = "oxide-postgres"
        port = "postgres"

        check {
          name     = "oxide-postgres-ready"
          type     = "tcp"
          interval = "10s"
          timeout  = "3s"

          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }
      }

      template {
        destination          = "secrets/postgres.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_USER     = {{ key "oxide/postgres/user" }}
POSTGRES_DB       = {{ key "oxide/postgres/db" }}
POSTGRES_PASSWORD = {{ key "oxide/postgres/password" }}
EOH
      }

      resources {
        cpu        = 300
        memory     = 128
        memory_max = 512
      }

      restart {
        attempts = 10
        interval = "10m"
        delay    = "15s"
        mode     = "delay"
      }
    }

    task "lavalink" {
      driver = "docker"

      config {
        image      = "ghcr.io/lavalink-devs/lavalink:4.2.2-alpine"
        ports      = ["lavalink"]
        force_pull = true

        volumes = [
          "local/application.yml:/opt/Lavalink/application.yml:ro",
        ]
      }

      env {
        TZ            = "Europe/Dublin"
        _JAVA_OPTIONS = "-Xms128M -Xmx512M"
      }

      service {
        name = "oxide-lavalink"
        port = "lavalink"

        check {
          name     = "oxide-lavalink-ready"
          type     = "tcp"
          interval = "10s"
          timeout  = "3s"

          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }
      }

      template {
        destination          = "secrets/lavalink.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
LAVALINK_SERVER_PASSWORD = {{ key "oxide/lavalink/password" }}
EOH
      }

      template {
        destination          = "local/application.yml"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
server:
  port: 2333
  address: 0.0.0.0

lavalink:
  plugins:
    - dependency: "dev.lavalink.youtube:youtube-plugin:1.18.1"
      snapshot: false
  server:
    password: "{{ key "oxide/lavalink/password" }}"
    sources:
      youtube: false
      bandcamp: false
      soundcloud: true
      twitch: false
      vimeo: false
      nico: false
      local: false
      http: true
    filters:
      volume: true
      equalizer: true
      karaoke: true
      timescale: true
      tremolo: true
      vibrato: true
      distortion: true
      rotation: true
      channelMix: true
      lowPass: true
    bufferDurationMs: 400
    frameBufferDurationMs: 5000
    opusEncodingQuality: 10
    resamplingQuality: HIGH
    trackStuckThresholdMs: 10000
    useSeekGhosting: true

plugins:
  youtube:
    enabled: true
    allowSearch: true
    allowDirectVideoIds: true
    allowDirectPlaylistIds: true
    clients:
      - MUSIC
      - ANDROID_MUSIC
      - ANDROID_VR
      - MWEB
      - WEB
      - TVHTML5_SIMPLY
      - WEBEMBEDDED
      - IOS

logging:
  level:
    root: INFO
    lavalink: INFO
    dev.lavalink.youtube.http.YoutubeAccessTokenTracker: WARN
    dev.lavalink.youtube.clients.skeleton.StreamingNonMusicClient: ERROR
  request:
    enabled: false
EOH
      }

      resources {
        cpu        = 500
        memory     = 288
        memory_max = 768
      }

      restart {
        attempts = 10
        interval = "10m"
        delay    = "15s"
        mode     = "delay"
      }
    }

    task "llama-cpp" {
      driver = "docker"

      config {
        image      = "ghcr.io/ggml-org/llama.cpp:server-b10015"
        ports      = ["llama_cpp"]
        force_pull = true

        args = [
          "-hf", "Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M",
          "--port", "8080",
          "--host", "0.0.0.0",
          "-c", "2048",
        ]

        volumes = [
          "/storage/nomad/oxide/llama-cpp:/root/.cache/llama.cpp",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      service {
        name = "oxide-llama-cpp"
        port = "llama_cpp"

        check {
          name     = "oxide-llama-cpp-ready"
          type     = "http"
          path     = "/health"
          interval = "15s"
          timeout  = "5s"

          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }
      }

      resources {
        cpu        = 1000
        memory     = 896
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
