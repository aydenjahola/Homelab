job "adventurelog" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    frontend = "trips.aydenjahola.com"
    backend  = "trips-api.aydenjahola.com"
  }

  group "adventurelog" {
    count = 1

    network {
      port "web" {
        to = 3000
      }

      port "server" {
        to = 80
      }

      port "db" {
        to = 5432
      }
    }

    service {
      name = "adventurelog-frontend"
      port = "web"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.adventurelog.rule=Host(`${NOMAD_META_frontend}`)",
        "traefik.http.routers.adventurelog.entrypoints=https",
      ]
    }

    task "web" {
      driver = "docker"

      config {
        image = "ghcr.io/seanmorley15/adventurelog-frontend:latest"
        ports = ["web"]

        volumes = [
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      resources {
        cpu    = 300
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
PUBLIC_SERVER_URL = https://{{ env "NOMAD_META_backend" }}
ORIGIN            = https://{{ env "NOMAD_META_frontend" }}
EOH
      }
    }

    service {
      name = "adventurelog-backend"
      port = "server"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.adventurelog-api.rule=Host(`${NOMAD_META_backend}`)",
        "traefik.http.routers.adventurelog-api.entrypoints=https",
      ]
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/seanmorley15/adventurelog-backend:latest"
        ports = ["server"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/media:/code/media:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
SECRET_KEY                   = {{ key "adventurelog/secret/key" }}

DJANGO_ADMIN_EMAIL           = {{ key "adventurelog/admin/email" }}
DJANGO_ADMIN_USERNAME        = {{ key "adventurelog/admin/user" }}
DJANGO_ADMIN_PASSWORD        = {{ key "adventurelog/admin/password" }}

PUBLIC_URL                   = https://{{ env "NOMAD_META_backend" }}
CSRF_TRUSTED_ORIGINS         = https://{{ env "NOMAD_META_frontend" }},https://{{ env "NOMAD_META_backend" }}
FRONTEND_URL                 = https://{{ env "NOMAD_META_frontend" }}

GOOGLE_MAPS_API_KEY          = {{ key "adventurelog/maps/api/key" }}

ACCOUNT_EMAIL_VERIFICATION   = "mandatory"

EMAIL_BACKEND                = email
EMAIL_USE_TLS                = True
EMAIL_PORT                   = 587
EMAIL_USE_SSL                = False
EMAIL_HOST                   = {{ key "adventurelog/smtp/host" }}
EMAIL_HOST_USER              = {{ key "adventurelog/smtp/user" }}
EMAIL_HOST_PASSWORD          = {{ key "adventurelog/smtp/password" }}
DEFAULT_FROM_EMAIL           = {{ key "adventurelog/smtp/from" }}

PGHOST                       = {{ env "NOMAD_IP_db" }}
PGPORT                       = {{ env "NOMAD_HOST_PORT_db" }}
PGDATABASE                   = {{ key "adventurelog/db/name" }}
PGUSER                       = {{ key "adventurelog/db/user" }}
PGPASSWORD                   = {{ key "adventurelog/db/password" }}

DISABLE_REGISTRATION         = True
DISABLE_REGISTRATION_MESSAGE = "Registration is disabled for this instance of AdventureLog."
EOH
      }
    }

    service {
      name = "adventurelog-db"
      port = "db"
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgis/postgis:17-3.6-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      resources {
        cpu    = 500
        memory = 768
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "adventurelog/db/name" }}
POSTGRES_USER     = {{ key "adventurelog/db/user" }}
POSTGRES_PASSWORD = {{ key "adventurelog/db/password" }}
EOH
      }
    }
  }
}

