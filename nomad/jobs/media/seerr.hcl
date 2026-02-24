job "seerr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "seerr.local.aydenjahola.com"
  }

  group "seerr" {
    count = 1

    network {
      port "http" {
        to = 5055
      }
    }

    service {
      name = "seerr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.seerr.entrypoints=https",
        "traefik.http.routers.seerr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "seerr" {
      driver = "docker"

      config {
        image = "ghcr.io/seerr-team/seerr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/config:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        LOG_LEVEL = "debug"
        TZ        = "Europe/Dublin"
      }

      resources {
        cpu    = 300
        memory = 900
      }
    }
  }
}
