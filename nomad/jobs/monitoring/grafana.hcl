job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "grafana.aydenjahola.com"
  }

  group "grafana" {
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
      port "http" {
        to = 3000
      }
    }

    service {
      name = "grafana"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.grafana.entrypoints=https",
        "traefik.http.routers.grafana.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_MAIN\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "grafana/db/user" }}
DB_MAIN = {{ key "grafana/db/name" }}
{{ range service "grafana-db" }}
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

    task "grafana" {
      driver = "docker"

      config {
        image = "grafana/grafana:13.3.0"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/grafana",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/plugins:/var/lib/grafana/plugins",
          "local/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml",
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
GF_SERVER_ROOT_URL = https://{{ env "NOMAD_META_domain" }}

GF_DATABASE_TYPE     = postgres
GF_DATABASE_HOST     = {{ range service "grafana-db" }}{{ .Address }}:{{ .Port }}{{ end }}
GF_DATABASE_NAME     = {{ key "grafana/db/name" }}
GF_DATABASE_USER     = {{ key "grafana/db/user" }}
GF_DATABASE_PASSWORD = {{ key "grafana/db/password" }}
GF_DATABASE_SSL_MODE = disable

GF_PLUGINS_PREINSTALL  = grafana-clock-panel
GF_USERS_ALLOW_SIGN_UP = false

GF_AUTH_ANONYMOUS_ENABLED = false
GF_AUTH_BASIC_ENABLED     = false

GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP = true
GF_AUTH_DISABLE_LOGIN_FORM                = true
GF_AUTH_OAUTH_AUTO_LOGIN                  = true
GF_AUTH_SIGNOUT_REDIRECT_URL              = {{ key "authentik/url" }}/application/o/grafana/end-session/

GF_AUTH_GENERIC_OAUTH_NAME                       = Authentik
GF_AUTH_GENERIC_OAUTH_ENABLED                    = true
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP              = false
GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH       = email
GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH       = preferred_username
GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH        = name
GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH      = groups
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH        = "contains(groups, 'homelab-admins') && 'GrafanaAdmin' || 'Viewer'"
GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN = true
GF_AUTH_GENERIC_OAUTH_USE_PKCE                   = true

GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = {{ key "authentik/oidc/grafana/client_id" }}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = {{ key "authentik/oidc/grafana/client_secret" }}
GF_AUTH_GENERIC_OAUTH_SCOPES        = openid profile email offline_access
GF_AUTH_GENERIC_OAUTH_AUTH_URL      = {{ key "authentik/url" }}/application/o/authorize/
GF_AUTH_GENERIC_OAUTH_TOKEN_URL     = {{ key "authentik/url" }}/application/o/token/
GF_AUTH_GENERIC_OAUTH_API_URL       = {{ key "authentik/url" }}/application/o/userinfo/
EOH
      }

      template {
        destination = "local/datasources.yml"
        data        = <<EOH
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: {{ range service "prometheus" }}http://{{ .Address }}:{{ .Port }}{{ end }}
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: https://loki.local.aydenjahola.com
    editable: true
EOH
      }

      resources {
        cpu        = 500
        memory     = 576
        memory_max = 800
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
      name = "grafana-db"
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
POSTGRES_USER     = {{ key "grafana/db/user" }}
POSTGRES_PASSWORD = {{ key "grafana/db/password" }}
POSTGRES_DB       = {{ key "grafana/db/name" }}
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
