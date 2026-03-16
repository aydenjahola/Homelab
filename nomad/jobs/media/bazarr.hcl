job "bazarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "bazarr.local.aydenjahola.com"
  }

  group "bazarr" {
    count = 1

    network {
      port "http" {
        to = 6767
      }
    }

    service {
      name = "bazarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.bazarr.entrypoints=https",
        "traefik.http.routers.bazarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "bazarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/bazarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/movies:/movies:rw",
          "/storage/jellyfin/tv:/tv:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
