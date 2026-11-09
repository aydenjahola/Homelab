job "authentik" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "auth.aydenjahola.com"
  }

  group "authentik" {
    count = 1

    update {
      healthy_deadline  = "10m"
      progress_deadline = "15m"
      max_parallel      = 1
      min_healthy_time  = "10s"
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
        to = 9000
      }

      port "metrics" {
        to = 9300
      }
    }

    service {
      name = "authentik"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.authentik.entrypoints=https",
        "traefik.http.routers.authentik.rule=Host(`${NOMAD_META_domain}`)",

        # Embedded outpost endpoints (login callback, sign_out) on every forward-auth host.
        "traefik.http.routers.authentik-outpost.entrypoints=https",
        "traefik.http.routers.authentik-outpost.rule=PathPrefix(`/outpost.goauthentik.io/`)",
        "traefik.http.routers.authentik-outpost.priority=1000",

        "traefik.http.middlewares.authentik.forwardauth.address=http://${NOMAD_ADDR_http}/outpost.goauthentik.io/auth/traefik",
        "traefik.http.middlewares.authentik.forwardauth.trustForwardHeader=false",
        "traefik.http.middlewares.authentik.forwardauth.authResponseHeaders=X-authentik-username,X-authentik-groups,X-authentik-entitlements,X-authentik-email,X-authentik-name,X-authentik-uid,X-authentik-jwt,X-authentik-meta-jwks,X-authentik-meta-outpost,X-authentik-meta-provider,X-authentik-meta-app,X-authentik-meta-version",
      ]

      check {
        name     = "authentik-http"
        type     = "http"
        path     = "/-/health/live/"
        interval = "10s"
        timeout  = "3s"

        check_restart {
          limit           = 3
          grace           = "120s"
          ignore_warnings = false
        }
      }
    }

    service {
      name = "authentik-metrics"
      port = "metrics"
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
DB_USER = {{ key "authentik/db/user" }}
DB_NAME = {{ key "authentik/db/name" }}
{{ range service "authentik-db" }}
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

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2026.8.5"
        ports = ["http", "metrics"]
        args  = ["server"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
AUTHENTIK_SECRET_KEY               = {{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED = false

AUTHENTIK_EMAIL__HOST     = {{ key "authentik/smtp/host" }}
AUTHENTIK_EMAIL__PORT     = {{ key "authentik/smtp/port" }}
AUTHENTIK_EMAIL__USERNAME = {{ key "authentik/smtp/username" }}
AUTHENTIK_EMAIL__PASSWORD = {{ key "authentik/smtp/password" }}
AUTHENTIK_EMAIL__USE_TLS  = true
AUTHENTIK_EMAIL__USE_SSL  = false
AUTHENTIK_EMAIL__TIMEOUT  = 10
AUTHENTIK_EMAIL__FROM     = "{{ key "authentik/smtp/from" }}"

AUTHENTIK_POSTGRESQL__NAME     = {{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER     = {{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD = {{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 960
        memory_max = 1024
      }
    }

    task "worker" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2026.8.5"
        args  = ["worker"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data:rw",
          "local/blueprints:/blueprints/custom:ro",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
AUTHENTIK_SECRET_KEY               = {{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED = false

AUTHENTIK_EMAIL__HOST     = {{ key "authentik/smtp/host" }}
AUTHENTIK_EMAIL__PORT     = {{ key "authentik/smtp/port" }}
AUTHENTIK_EMAIL__USERNAME = {{ key "authentik/smtp/username" }}
AUTHENTIK_EMAIL__PASSWORD = {{ key "authentik/smtp/password" }}
AUTHENTIK_EMAIL__USE_TLS  = true
AUTHENTIK_EMAIL__USE_SSL  = false
AUTHENTIK_EMAIL__TIMEOUT  = 10
AUTHENTIK_EMAIL__FROM     = "{{ key "authentik/smtp/from" }}"

AUTHENTIK_BOOTSTRAP_PASSWORD = {{ key "authentik/bootstrap/password" }}
AUTHENTIK_BOOTSTRAP_EMAIL    = {{ key "authentik/bootstrap/email" }}

AUTHENTIK_POSTGRESQL__NAME     = {{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER     = {{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD = {{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      dynamic "template" {
        for_each = fileset(".", "jobs/services/authentik/blueprints/*.yaml")

        content {
          error_on_missing_key = true
          data                 = file(template.value)
          destination          = "local/blueprints/${basename(template.value)}"
          change_mode          = "noop"
        }
      }

      resources {
        cpu        = 500
        memory     = 576
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
      name = "authentik-db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
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
POSTGRES_DB       = {{ key "authentik/db/name" }}
POSTGRES_USER     = {{ key "authentik/db/user" }}
POSTGRES_PASSWORD = {{ key "authentik/db/password" }}
EOH
      }

      resources {
        cpu        = 300
        memory     = 192
        memory_max = 512
      }
    }
  }
}
