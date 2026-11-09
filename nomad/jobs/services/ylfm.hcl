job "your-lastfm" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ylfm.local.aydenjahola.com"
  }

  group "your-lastfm" {
    count = 1

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
      port "http" {
        to = 1533
      }
    }

    service {
      name = "your-lastfm"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.your-lastfm.entrypoints=https",
        "traefik.http.routers.your-lastfm.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.your-lastfm.middlewares=authentik@consulcatalog",
      ]
    }

    task "your-lastfm" {
      driver = "docker"

      config {
        image = "gomaink/your-lastfm:1.3.0"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/data",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
LASTFM_API_KEY  = {{ key "your-lastfm/api/key" }}
LASTFM_USERNAME = {{ key "your-lastfm/username" }}
EOH
      }

      resources {
        cpu        = 300
        memory     = 160
        memory_max = 300
      }
    }
  }
}
