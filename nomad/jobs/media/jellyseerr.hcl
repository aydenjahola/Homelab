job "jellyseerr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellyseerr.local.aydenjahola.com"
  }

  group "jellyseerr" {
    count = 1

    network {
      port "http" {
        to = 5055
      }
    }

    service {
      name = "jellyseerr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyseerr.entrypoints=https",
        "traefik.http.routers.jellyseerr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "jellyseerr" {
      driver = "docker"

      config {
        image = "fallenbagel/jellyseerr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/app/config:rw",
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
