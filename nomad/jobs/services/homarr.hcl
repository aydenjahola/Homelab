job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "home.aydenjahola.com"
  }

  group "homarr" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
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
      port "http" {
        to = 7575
      }
    }

    service {
      name = "homarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.homarr.entrypoints=https",
        "traefik.http.routers.homarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "homarr/db/user" }}
DB_NAME = {{ key "homarr/db/name" }}
{{ range service "homarr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "homarr" {
      driver = "docker"

      config {
        image = "ghcr.io/homarr-labs/homarr:v2.12.0"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/configs:/app/data/configs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/icons:/app/public/icons:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/appdata:rw",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
EDIT_MODE_PASSWORD    = {{ key "homarr/edit/password" }}
DISABLE_EDIT_MODE     = {{ key "homarr/edit/disable" }}
DEFAULT_COLOR_SCHEME  = {{ key "homarr/default/color" }}
SECRET_ENCRYPTION_KEY = {{ key "homarr/encryption/key" }}

DB_DRIVER  = {{ key "homarr/db/driver" }}
DB_DIALECT = {{ key "homarr/db/dialect" }}

{{ range service "homarr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}

DB_NAME     = {{ key "homarr/db/name" }}
DB_USER     = {{ key "homarr/db/user" }}
DB_PASSWORD = {{ key "homarr/db/password" }}

REDIS_IS_EXTERNAL = true

{{ range service "homarr-redis" }}
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}
{{ end }}

AUTH_PROVIDERS           = oidc
AUTH_OIDC_ISSUER         = {{ key "authentik/url" }}/application/o/homarr/
AUTH_OIDC_CLIENT_ID      = {{ key "authentik/oidc/homarr/client_id" }}
AUTH_OIDC_CLIENT_SECRET  = {{ key "authentik/oidc/homarr/client_secret" }}
AUTH_OIDC_CLIENT_NAME    = Authentik
AUTH_OIDC_AUTO_LOGIN     = true
AUTH_LOGOUT_REDIRECT_URL = {{ key "authentik/url" }}/application/o/homarr/end-session/
EOH
      }

      resources {
        cpu        = 500
        memory     = 480
        memory_max = 1024
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
      name = "homarr-db"
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

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_USER     = {{ key "homarr/db/user" }}
POSTGRES_DB       = {{ key "homarr/db/name" }}
POSTGRES_PASSWORD = {{ key "homarr/db/password" }}
EOH
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 256
      }
    }
  }

  group "redis" {
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
      port "redis" {
        to = 6379
      }
    }

    service {
      name = "homarr-redis"
      port = "redis"

      check {
        name     = "redis-ready"
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

    task "redis" {
      driver = "docker"

      config {
        image = "redis:8.8.0-alpine"
        ports = ["redis"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data",
        ]
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 256
      }
    }
  }
}
