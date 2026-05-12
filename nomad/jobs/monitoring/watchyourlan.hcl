job "watchyourlan" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "wyl.local.aydenjahola.com"
  }

  group "watchyourlan" {
    count = 1

    network {
      mode = "host"

      port "http" {
        static = 8840
        to     = 8840
      }
    }

    service {
      name = "watchyourlan"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.watchyourlan.entrypoints=https",
        "traefik.http.routers.watchyourlan.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "watchyourlan-http"
        type     = "http"
        path     = "/"
        port     = "http"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "watchyourlan" {
      driver = "docker"

      config {
        image        = "aceberg/watchyourlan:v2"
        network_mode = "host"

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data/WatchYourLAN",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
TZ=Europe/Dublin

HOST=0.0.0.0
PORT=8840

IFACES={{ key "watchyourlan/ifaces" }}

THEME=materia
COLOR=dark

SHOUTRRR_URL={{ key "watchyourlan/shoutrrr/url" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
