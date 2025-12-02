job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ha.local.aydenjahola.com"
  }

  group "home-assistant" {
    count = 1

    network {
      port "http" {
        to = 8123
      }
    }

    service {
      name = "home-assistant"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ha.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.ha.entrypoints=https",
      ]
    }

    task "home-assistant" {
      driver = "docker"

      config {
        image = "ghcr.io/home-assistant/home-assistant:stable"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/config:/config:rw",
          "/etc/localtime:/etc/localtime:ro",
          "/run/dbus:/run/dbus:ro",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
