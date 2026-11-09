job "homelab-docs" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "docs.local.aydenjahola.com"
  }

  group "homelab-docs" {
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
        to = 80
      }
    }

    service {
      name = "homelab-docs"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.docs.entrypoints=https",
        "traefik.http.routers.docs.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.docs.middlewares=authentik@consulcatalog",
      ]
    }

    task "mkdocs" {
      driver = "docker"

      config {
        image      = "ghcr.io/aydenjahola/homelab-docs:sha-28a047d"
        force_pull = true
        ports      = ["http"]

        auth {
          username = "${DOCKER_USER}"
          password = "${DOCKER_PASS}"
        }
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
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
