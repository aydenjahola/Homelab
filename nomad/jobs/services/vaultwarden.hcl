job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "vault.aydenjahola.com"
  }

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vault.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.vault.entrypoints=https",
      ]
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
ADMIN_TOKEN={{ key "vaultwarden/admin/token" }}

DOMAIN={{ key "vaultwarden/domain" }}

WEBSOCKET_ENABLED=true

SIGNUPS_ALLOWED=false
SIGNUPS_VERIFY=true
SIGNUPS_VERIFY_RESEND_TIME=3600
SIGNUPS_VERIFY_RESEND_LIMIT=6

SMTP_HOST={{ key "vaultwarden/smtp/host" }}
SMTP_FROM={{ key "vaultwarden/smtp/from" }}
SMTP_PORT={{ key "vaultwarden/smtp/port" }}
SMTP_USERNAME={{ key "vaultwarden/smtp/username" }}
SMTP_PASSWORD={{ key "vaultwarden/smtp/password" }}


DATABASE_URL=postgresql://{{ key "vaultwarden/db/user" }}:{{ key "vaultwarden/db/password" }}@{{ env "NOMAD_ADDR_db" }}/{{ key "vaultwarden/db/name" }}

PUSH_ENABLED=true
PUSH_INSTALLATION_ID={{ key "vaultwarden/install/id" }}
PUSH_INSTALLATION_KEY={{ key "vaultwarden/install/key" }}
PUSH_RELAY_URI=https://api.bitwarden.eu
PUSH_IDENTITY_URI=https://identity.bitwarden.eu
EOH
      }
    }

    service {
      name = "vaultwarden-db"
      port = "db"
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_NAME={{ key "vaultwarden/db/name" }}
POSTGRES_USER={{ key "vaultwarden/db/user" }}
POSTGRES_PASSWORD={{ key "vaultwarden/db/password" }}
EOH
      }
    }
  }
}
