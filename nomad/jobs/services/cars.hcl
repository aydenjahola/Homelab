# Basic-auth users string for the Traefik cars-auth middleware (htpasswd format,
# e.g. "admin:$apr1$..."). Traefik tags cannot read Consul KV, so it is passed
# at deploy time instead of being committed:
#   NOMAD_VAR_cars_basicauth_users='admin:...' nomad job run jobs/services/cars.hcl
variable "cars_basicauth_users" {
  type = string
}

job "cars" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "cars.aydenjahola.com"
  }

  group "cars" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
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
      port "http" {
        to = 3000
      }
    }

    service {
      name = "cars"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.cars.entrypoints=https",
        "traefik.http.routers.cars.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.cars.middlewares=cars-auth",
        "traefik.http.middlewares.cars-auth.basicauth.users=${var.cars_basicauth_users}",
      ]

      check {
        name     = "cars-http"
        type     = "http"
        path     = "/api/health"
        interval = "30s"
        timeout  = "10s"

        check_restart {
          limit           = 3
          grace           = "300s"
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

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "cars/db/user" }}
DB_MAIN = {{ key "cars/db/name" }}
{{ range service "cars-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    task "cars" {
      driver = "docker"

      config {
        image      = "ghcr.io/aydenjahola/cars:bd4a0bf"
        ports      = ["http"]
        force_pull = true

        auth {
          username = "${DOCKER_USER}"
          password = "${DOCKER_PASS}"
        }
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
DOCKER_USER = {{ key "cars/ghcr/username" }}
DOCKER_PASS = {{ key "cars/ghcr/password" }}

NODE_ENV = production

APP_URL = https://{{ env "NOMAD_META_domain" }}

DATABASE_URL = {{ range service "cars-db" }}postgresql://{{ key "cars/db/user" | urlquery }}:{{ key "cars/db/password" | urlquery }}@{{ .Address }}:{{ .Port }}/{{ key "cars/db/name" | urlquery }}{{ end }}

SCRAPE_INTERVAL_MINUTES = 60

FLARESOLVERR_URL     = {{ keyOrDefault "cars/flaresolverr/url" "https://flaresolverr.local.aydenjahola.com/" }}
FLARESOLVERR_ENABLED = {{ keyOrDefault "cars/flaresolverr/enabled" "true" }}

SMTP_HOST = {{ key "cars/smtp/host" }}
SMTP_PORT = 587
SMTP_USER = {{ key "cars/smtp/user" }}
SMTP_PASS = {{ key "cars/smtp/password" }}
SMTP_FROM = {{ key "cars/smtp/from" }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 1184
        memory_max = 1536
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
      port "db" {
        to = 5432
      }
    }

    service {
      name = "cars-db"
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
POSTGRES_DB       = {{ key "cars/db/name" }}
POSTGRES_USER     = {{ key "cars/db/user" }}
POSTGRES_PASSWORD = {{ key "cars/db/password" }}
EOH
      }

      resources {
        cpu        = 300
        memory     = 128
        memory_max = 512
      }
    }
  }
}
