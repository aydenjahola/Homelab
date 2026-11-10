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
      auto_revert       = false
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

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "postgres:17-alpine"
        command = "sh"

        args = [
          "-c",
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_MAIN\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "watchyourlan/db/user" }}
DB_MAIN = {{ key "watchyourlan/db/name" }}
{{ range service "watchyourlan-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
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
        perms                = "0600"
        change_mode          = "restart"
        error_on_missing_key = true
        data                 = <<EOH
TZ = Europe/Dublin

HOST = 0.0.0.0
PORT = 8840

IFACES = {{ key "watchyourlan/ifaces" }}

THEME = materia
COLOR = dark

SHOUTRRR_URL = {{ key "watchyourlan/shoutrrr/url" }}

USE_DB     = postgres
PG_CONNECT = postgres://{{ key "watchyourlan/db/user" }}:{{ key "watchyourlan/db/password" }}@{{ range service "watchyourlan-db" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "watchyourlan/db/name" }}?sslmode=disable
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 512
      }
    }
  }

  group "db" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = false
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
      port "db" {
        to = 5432
      }
    }

    service {
      name = "watchyourlan-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_USER     = {{ key "watchyourlan/db/user" }}
POSTGRES_PASSWORD = {{ key "watchyourlan/db/password" }}
POSTGRES_DB       = {{ key "watchyourlan/db/name" }}
EOH
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 256
      }
    }
  }
}
