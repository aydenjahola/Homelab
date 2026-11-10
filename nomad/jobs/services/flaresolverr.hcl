job "flaresolverr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "flaresolverr.local.aydenjahola.com"
  }

  group "flaresolverr" {
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
        to = 8191
      }
    }

    service {
      name = "flaresolverr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.flaresolverr.entrypoints=https",
        "traefik.http.routers.flaresolverr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "flaresolverr" {
      driver = "docker"

      config {
        image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2"
        ports = ["http"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
TZ             = Europe/Dublin
LOG_LEVEL      = info
LOG_HTML       = false
CAPTCHA_SOLVER = none
EOH
      }

      resources {
        cpu        = 1500
        memory     = 4608
        memory_max = 6144
      }
    }
  }
}
