job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "vault.aydenjahola.com"
  }

  group "vaultwarden" {
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
        to = 80
      }
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vault.entrypoints=https",
        "traefik.http.routers.vault.rule=Host(`${NOMAD_META_domain}`)",
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
DB_USER = {{ key "vaultwarden/db/user" }}
DB_NAME = {{ key "vaultwarden/db/name" }}
{{ range service "vaultwarden-db" }}
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

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:1.37.5"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
ADMIN_TOKEN = {{ key "vaultwarden/admin/token" }}

DOMAIN = {{ key "vaultwarden/domain" }}

SSO_ENABLED             = true
SSO_ONLY                = true
SSO_SIGNUPS_MATCH_EMAIL = true
SSO_AUTHORITY           = {{ key "authentik/url" }}/application/o/vaultwarden/
SSO_SCOPES              = "openid profile email offline_access"
SSO_CLIENT_ID           = {{ key "authentik/oidc/vaultwarden/client_id" }}
SSO_CLIENT_SECRET       = {{ key "authentik/oidc/vaultwarden/client_secret" }}

WEBSOCKET_ENABLED = true

SIGNUPS_ALLOWED             = false
SIGNUPS_VERIFY              = true
SIGNUPS_VERIFY_RESEND_TIME  = 3600
SIGNUPS_VERIFY_RESEND_LIMIT = 6

SMTP_HOST     = {{ key "vaultwarden/smtp/host" }}
SMTP_FROM     = {{ key "vaultwarden/smtp/from" }}
SMTP_PORT     = {{ key "vaultwarden/smtp/port" }}
SMTP_USERNAME = {{ key "vaultwarden/smtp/username" }}
SMTP_PASSWORD = {{ key "vaultwarden/smtp/password" }}


DATABASE_URL = postgresql://{{ key "vaultwarden/db/user" }}:{{ key "vaultwarden/db/password" }}@{{ range service "vaultwarden-db" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "vaultwarden/db/name" }}

PUSH_ENABLED          = true
PUSH_INSTALLATION_ID  = {{ key "vaultwarden/install/id" }}
PUSH_INSTALLATION_KEY = {{ key "vaultwarden/install/key" }}
PUSH_RELAY_URI        = https://api.bitwarden.eu
PUSH_IDENTITY_URI     = https://identity.bitwarden.eu
EOH
      }

      resources {
        cpu        = 500
        memory     = 160
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
      name = "vaultwarden-db"
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
POSTGRES_NAME     = {{ key "vaultwarden/db/name" }}
POSTGRES_USER     = {{ key "vaultwarden/db/user" }}
POSTGRES_PASSWORD = {{ key "vaultwarden/db/password" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 300
      }
    }
  }
}
