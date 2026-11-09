job "watchyourlan" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "wyl.local.aydenjahola.com"
  }

  group "watchyourlan" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

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
        "traefik.http.routers.watchyourlan.middlewares=authentik@consulcatalog",
      ]

      check {
        name     = "watchyourlan-http"
        type     = "http"
        path     = "/"
        port     = "http"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "watchyourlan" {
      driver = "docker"

      config {
        image        = "aceberg/watchyourlan:2.1.4"
        network_mode = "host"

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data/WatchYourLAN",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        change_mode          = "restart"
        error_on_missing_key = true
        data                 = <<EOH
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
        cpu        = 300
        memory     = 64
        memory_max = 512
      }
    }
  }
}
