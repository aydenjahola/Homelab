job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellyfin.local.aydenjahola.com"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "thor"
  }

  group "jellyfin" {
    count = 1

    network {
      port "http" {
        to = 8096
      }
    }

    service {
      name = "jellyfin"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyfin.entrypoints=https",
        "traefik.http.routers.jellyfin.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "jellyfin" {
      driver = "docker"

      resources {
        cpu    = 1000
        memory = 1024
      }

      config {
        image = "lscr.io/linuxserver/jellyfin:latest"
        ports = ["http"]

        devices = [
          {
            host_path      = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]

        volumes = [
          "/home/ayden/${NOMAD_JOB_NAME}/data:/config:rw", # some weird NFS issues, upgraded to v4 since but never tested if there are still issues
          "/storage/jellyfin/tv:/data/tvshows:rw",
          "/storage/jellyfin/movies:/data/movies:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        PUID          = "1000"
        PGID          = "1000"
        TZ            = "Europe/Dublin"
        SUP_GROUP_IDS = "109,44"
        JELLYFIN_PublishedServerUrl = "https://${NOMAD_META_domain}"
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
