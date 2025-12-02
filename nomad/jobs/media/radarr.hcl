job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "radarr.local.aydenjahola.com"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "thor"
  }

  group "radarr" {
    count = 1

    network {
      port "http" {
        to = 7878
      }
    }

    service {
      name = "radarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.radarr.entrypoints=https",
        "traefik.http.routers.radarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "radarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/radarr:latest"
        ports = ["http"]

        volumes = [
          "/home/ayden/${NOMAD_JOB_NAME}/data:/config:rw", # some weird NFS issues, upgraded to v4 since but never tested if there are still issues
          "/storage/jellyfin/movies:/movies:rw",
          "/storage/jellyfin/downloads:/downloads:rw",
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
