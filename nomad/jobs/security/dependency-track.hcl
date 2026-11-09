job "dependency-track" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "dtrack.local.aydenjahola.com"
  }

  group "dependency-track" {
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
      port "api" {
        to = 8080
      }
      port "health" {
        to = 9000
      }
      port "web" {
        to = 8080
      }
    }

    service {
      name = "dependency-track-api"
      port = "api"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dtrack-api.entrypoints=https",
        "traefik.http.routers.dtrack-api.rule=Host(`${NOMAD_META_domain}`) && PathPrefix(`/api`)",
      ]

      check {
        name     = "dependency-track-http"
        type     = "http"
        port     = "health"
        path     = "/health/ready"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "120s"
          ignore_warnings = false
        }
      }
    }

    service {
      name = "dependency-track"
      port = "web"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dtrack.entrypoints=https",
        "traefik.http.routers.dtrack.rule=Host(`${NOMAD_META_domain}`)",
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
DB_USER = {{ key "dependency-track/db/user" }}
DB_NAME = {{ key "dependency-track/db/name" }}
{{ range service "dependency-track-db" }}
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

    task "apiserver" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image        = "ghcr.io/dependencytrack/apiserver:5.2.1"
        ports        = ["api", "health"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges:true"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        change_mode          = "restart"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
{{- range service "dependency-track-db" }}
DT_DATASOURCE_URL=jdbc:postgresql://{{ .Address }}:{{ .Port }}/{{ key "dependency-track/db/name" }}
{{- end }}
DT_DATASOURCE_USERNAME = {{ key "dependency-track/db/user" }}
DT_DATASOURCE_PASSWORD = {{ key "dependency-track/db/password" }}

DT_OUTBOUND_ALLOWED_DESTINATIONS = external,trivy.local.aydenjahola.com

TZ = Europe/Dublin

DT_OIDC_ENABLED              = true
DT_OIDC_ISSUER               = {{ key "authentik/url" }}/application/o/dependency-track/
DT_OIDC_CLIENT_ID            = {{ key "authentik/oidc/dependency-track/client_id" }}
DT_OIDC_USERNAME_CLAIM       = preferred_username
DT_OIDC_USER_PROVISIONING    = true
DT_OIDC_TEAMS_CLAIM          = groups
DT_OIDC_TEAM_SYNCHRONIZATION = true
EOH
      }

      resources {
        cpu        = 1500
        memory     = 864
        memory_max = 3072
      }
    }

    task "frontend" {
      driver = "docker"

      config {
        image        = "ghcr.io/dependencytrack/frontend:5.2.1"
        ports        = ["web"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges:true"]
      }

      env = {
        "API_BASE_URL"           = "https://${NOMAD_META_domain}"
        "OIDC_CLIENT_ID"         = "dependency-track"
        "OIDC_SCOPE"             = "openid profile email"
        "OIDC_LOGIN_BUTTON_TEXT" = "Login with Authentik"
      }

      template {
        destination          = "local/oidc.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
OIDC_ISSUER = {{ key "authentik/url" }}/application/o/dependency-track/
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
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
      name = "dependency-track-db"
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
        image        = "postgres:18-alpine"
        ports        = ["db"]
        security_opt = ["no-new-privileges:true"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql:rw",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_DB       = {{ key "dependency-track/db/name" }}
POSTGRES_USER     = {{ key "dependency-track/db/user" }}
POSTGRES_PASSWORD = {{ key "dependency-track/db/password" }}
TZ                = Europe/Dublin
EOH
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 1024
      }
    }
  }
}
