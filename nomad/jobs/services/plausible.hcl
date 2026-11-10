job "plausible" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "plausible.aydenjahola.com"
  }

  group "plausible" {
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
        to = 8000
      }
    }

    service {
      name = "plausible"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.plausible.entrypoints=https",
        "traefik.http.routers.plausible.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "postgres:16-alpine"
        command = "sh"

        args = [
          "-c",
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done; until wget -qO- \"http://$CH_HOST:$CH_PORT/ping\" >/dev/null 2>&1; do echo waiting for clickhouse; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "plausible/db/user" }}
DB_NAME = {{ key "plausible/db/name" }}
{{ range service "plausible-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
{{ range service "plausible-clickhouse" }}
CH_HOST={{ .Address }}
CH_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }
    }

    task "plausible" {
      driver = "docker"

      config {
        image = "ghcr.io/plausible/community-edition:v3.2.1"
        ports = ["http"]

        command = "/bin/sh"
        args    = ["-c", "/entrypoint.sh db createdb && /entrypoint.sh db migrate && /entrypoint.sh run"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/var/lib/plausible",
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
DISABLE_REGISTRATION = true

SECRET_KEY_BASE = {{ key "plausible/secret/key" }}
BASE_URL        = https://{{ env "NOMAD_META_domain" }}
TOTP_VAULT_KEY  = {{ key "plausible/totp/key" }}

MAXMIND_LICENSE_KEY = {{ key "plausible/maxmind/license" }}
MAXMIND_EDITION     = GeoLite2-City

GOOGLE_CLIENT_ID     = {{ key "plausible/google/client/id" }}
GOOGLE_CLIENT_SECRET = {{ key "plausible/google/client/secret" }}

DATABASE_URL = postgres://{{ key "plausible/db/user" }}:{{ key "plausible/db/password" }}@{{ range service "plausible-db" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "plausible/db/name" }}

CLICKHOUSE_DATABASE_URL = http://{{ range service "plausible-clickhouse" }}{{ .Address }}:{{ .Port }}{{ end }}/plausible_events_db

TMPDIR = /var/lib/plausible/tmp

MAILER_EMAIL   = {{ key "plausible/smtp/from" }}
MAILER_NAME    = {{ key "plausible/smtp/name" }}
SMTP_HOST_ADDR = {{ key "plausible/smtp/host" }}
SMTP_HOST_PORT = {{ key "plausible/smtp/port" }}
SMTP_USER_NAME = {{ key "plausible/smtp/username" }}
SMTP_USER_PWD  = {{ key "plausible/smtp/password" }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 960
        memory_max = 3072
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
        to = "5432"
      }
      port "clickhouse" {
        to = "8123"
      }
    }

    service {
      name = "plausible-db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/db/data-pg17:/var/lib/postgresql/data",
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
POSTGRES_USER     = {{ key "plausible/db/user" }}
POSTGRES_NAME     = {{ key "plausible/db/name" }}
POSTGRES_PASSWORD = {{ key "plausible/db/password" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 256
      }
    }

    service {
      name = "plausible-clickhouse"
      port = "clickhouse"

      check {
        name     = "clickhouse-ping"
        type     = "http"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "clickhouse" {
      driver = "docker"

      config {
        image = "clickhouse/clickhouse-server:24.12.6.70-alpine"
        ports = ["clickhouse"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/event-data:/var/lib/clickhouse",
          "/storage/nomad/${NOMAD_JOB_NAME}/event-logs:/var/log/clickhouse-server",
          "local/clickhouse-config.xml:/etc/clickhouse-server/config.d/logging.xml:ro",
          "local/clickhouse-user-config.xml:/etc/clickhouse-server/users.d/logging.xml:ro",
          "local/clickhouse-ipv4-only.xml:/etc/clickhouse-server/config.d/ipv4-only.xml:ro",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
CLICKHOUSE_SKIP_USER_SETUP = 1
EOH
      }

      template {
        destination = "local/clickhouse-ipv4-only.xml"
        data        = <<EOH
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOH
      }

      template {
        destination = "local/clickhouse-config.xml"
        data        = <<EOH
<clickhouse>
    <logger>
        <level>warning</level>
        <console>true</console>
    </logger>

    <!-- Stop all the unnecessary logging -->
    <query_thread_log remove="remove"/>
    <query_log remove="remove"/>
    <text_log remove="remove"/>
    <trace_log remove="remove"/>
    <metric_log remove="remove"/>
    <asynchronous_metric_log remove="remove"/>
    <session_log remove="remove"/>
    <part_log remove="remove"/>
</clickhouse>
EOH
      }

      template {
        destination = "local/clickhouse-user-config.xml"
        data        = <<EOH
<clickhouse>
    <profiles>
        <default>
            <log_queries>0</log_queries>
            <log_query_threads>0</log_query_threads>
        </default>
    </profiles>
</clickhouse>
EOH
      }

      resources {
        cpu        = 500
        memory     = 672
        memory_max = 800
      }
    }
  }
}
