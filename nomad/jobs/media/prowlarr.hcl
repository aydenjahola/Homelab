job "prowlarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prowl.local.aydenjahola.com"
  }

  group "prowlarr" {
    count = 1

    network {
      port "http" {
        to = 9696
      }
    }

    service {
      name = "prowlarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.prowl.entrypoints=https",
        "traefik.http.routers.prowl.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "prowlarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/prowlarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      resources {
        cpu    = 300
        memory = 512
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }
    }
  }
}
