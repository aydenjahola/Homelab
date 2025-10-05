job "uptime-kuma" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "status.aydenjahola.com"
  }

  group "uptime-kuma" {
    count = 1

    network {
      port "http" {
        to = 3001
      }
    }

    service {
      name = "uptime-kuma"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.uptime-kuma.entrypoints=https",
        "traefik.http.routers.uptime-kuma.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "uptime-kuma" {
      driver = "docker"

      config {
        image = "louislam/uptime-kuma:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/app/data:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
