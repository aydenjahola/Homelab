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
        "traefik.http.routers.authentik.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.authentik.entrypoints=https",
      ]

      check {
        name     = "authentik-live"
        type     = "http"
        path     = "/-/health/live/"
        interval = "10s"
        timeout  = "3s"
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for authentik db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "authentik/db/user" }}
DB_NAME={{ key "authentik/db/name" }}

{{ range service "authentik-db" }}
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
AUTHENTIK_SECRET_KEY={{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED=false

AUTHENTIK_POSTGRESQL__NAME={{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER={{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD={{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
AUTHENTIK_SECRET_KEY={{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED=false

AUTHENTIK_BOOTSTRAP_PASSWORD={{ key "authentik/bootstrap/password" }}
AUTHENTIK_BOOTSTRAP_EMAIL={{ key "authentik/bootstrap/email" }}

AUTHENTIK_POSTGRESQL__NAME={{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER={{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD={{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      dynamic "template" {
        for_each = fileset(".", "jobs/services/authentik/blueprints/*.yaml")

        content {
          data        = file(template.value)
          destination = "local/blueprints/${basename(template.value)}"
          change_mode = "noop"
        }
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }

  group "db" {
    count = 1

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

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "authentik/db/name" }}
POSTGRES_USER     = {{ key "authentik/db/user" }}
POSTGRES_PASSWORD = {{ key "authentik/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
