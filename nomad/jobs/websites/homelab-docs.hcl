job "homelab-docs" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "docs.local.aydenjahola.com"
  }

  group "homelab-docs" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "homelab-docs"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.docs.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.docs.entrypoints=https",
      ]
    }

    task "mkdocs" {
      driver = "docker"

      config {
        image      = "ghcr.io/aydenjahola/homelab-docs:latest"
        force_pull = true
        ports      = ["http"]

        auth {
          username = "${DOCKER_USER}"
          password = "${DOCKER_PASS}"
        }
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DOCKER_USER={{ key "docker/ghcr/user" }}
DOCKER_PASS={{ key "docker/ghcr/token" }}
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
