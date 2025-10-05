job "plausible" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "plausible.aydenjahola.com"
  }

  group "plausible" {
    count = 1

    network {
      port "http" {
        to = 8000
      }
      port "db" {
        to = "5432"
      }
      port "clickhouse" {
        to = "8123"
      }
    }

    service {
      name = "plausible"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.plausible.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.plausible.entrypoints=https",
      ]
    }

    service {
      name = "plausible-db"
      port = "db"
    }   

    task "db" {
      driver = "docker"

      config {
        image = "postgres:16-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/db/data:/var/lib/postgresql/data"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
POSTGRES_USER={{ key "plausible/db/user" }}
POSTGRES_NAME={{ key "plausible/db/name" }}
POSTGRES_PASSWORD={{ key "plausible/db/password" }}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    service {
      name = "plausible-clickhouse"
      port = "clickhouse"
    }

    task "clickhouse" {
      driver = "docker"

      config {
        image = "clickhouse/clickhouse-server:24.12-alpine"
        ports  = ["clickhouse"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/event-data:/var/lib/clickhouse",
          "/storage/nomad/${NOMAD_JOB_NAME}/event-logs:/var/log/clickhouse-server",
          "local/clickhouse-config.xml:/etc/clickhouse-server/config.d/logging.xml:ro",
          "local/clickhouse-user-config.xml:/etc/clickhouse-server/users.d/logging.xml:ro",
          "local/clickhouse-ipv4-only.xml:/etc/clickhouse-server/config.d/ipv4-only.xml:ro"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
CLICKHOUSE_SKIP_USER_SETUP=1
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
        cpu    = 300
        memory = 512
      }
    }

    task "plausible" {
      driver = "docker"

      config {
        image = "ghcr.io/plausible/community-edition:latest"
        ports = ["http"]

        command = "/bin/sh"
        args    = ["-c", "sleep 10 && /entrypoint.sh db createdb && /entrypoint.sh db migrate && /entrypoint.sh run"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/var/lib/plausible",
        ]
      }
      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
DISABLE_REGISTRATION=true

SECRET_KEY_BASE={{ key "plausible/secret/key" }}
BASE_URL=https://{{ env "NOMAD_META_domain" }}
TOTP_VAULT_KEY={{ key "plausible/totp/key" }}

MAXMIND_LICENSE_KEY={{ key "plausible/maxmind/license" }}
MAXMIND_EDITION=GeoLite2-City

GOOGLE_CLIENT_ID={{ key "plausible/google/client/id" }}
GOOGLE_CLIENT_SECRET={{ key "plausible/google/client/secret" }}

DATABASE_URL=postgres://{{ key "plausible/db/user" }}:{{ key "plausible/db/password" }}@{{ env "NOMAD_ADDR_db" }}/{{ key "plausible/db/name" }}

CLICKHOUSE_DATABASE_URL=http://{{ env "NOMAD_ADDR_clickhouse" }}/plausible_events_db

TMPDIR=/var/lib/plausible/tmp

MAILER_EMAIL={{ key "plausible/smtp/from" }}
MAILER_NAME={{ key "plausible/smtp/name" }}
SMTP_HOST_ADDR={{ key "plausible/smtp/host" }}
SMTP_HOST_PORT={{ key "plausible/smtp/port" }}
SMTP_USER_NAME={{ key "plausible/smtp/username" }}
SMTP_USER_PWD={{ key "plausible/smtp/password" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 3072
      }
    }
  }
}
