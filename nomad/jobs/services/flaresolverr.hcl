job "flaresolverr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "flaresolverr.local.aydenjahola.com"
  }

  group "flaresolverr" {
    count = 1

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
        "traefik.http.routers.flaresolverr.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.flaresolverr.entrypoints=https",
      ]
    }

    task "flaresolverr" {
      driver = "docker"

      config {
        image = "ghcr.io/flaresolverr/flaresolverr:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
TZ=Europe/Dublin
LOG_LEVEL=info
LOG_HTML=false
CAPTCHA_SOLVER=none
EOH
      }
    }
  }
}
