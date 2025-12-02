job "sonarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sonarr.local.aydenjahola.com"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "thor"
  }

  group "sonarr" {
    count = 1

    network {
      port "http" {
        to = 8989
      }
    }

    service {
      name = "sonarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.sonarr.entrypoints=https",
        "traefik.http.routers.sonarr.rule=Host(`${NOMAD_META_domain}`)"
      ]
    }

    task "sonarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/sonarr:latest"
        ports = ["http"]

        volumes = [
          "/home/ayden/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/tv:/tv:rw",
          "/storage/jellyfin/downloads:/downloads:rw",
          "/etc/localtime:/etc/localtime:ro"
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
