job "prowlarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prowl.local.aydenjahola.com"
  }

  group "prowlarr" {
    count = 1

    network {
      port "http" {
        to = 9696
      }
    }

    service {
      name = "prowlarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.prowl.entrypoints=https",
        "traefik.http.routers.prowl.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$PROWLARR__POSTGRES__HOST\" -p \"$PROWLARR__POSTGRES__PORT\" -U \"$PROWLARR__POSTGRES__USER\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
PROWLARR__POSTGRES__USER={{ key "prowlarr/db/user" }}

{{ range service "prowlarr-db" }}
PROWLARR__POSTGRES__HOST={{ .Address }}
PROWLARR__POSTGRES__PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "prowlarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/prowlarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
PUID=1000
PGID=1000
TZ=Europe/Dublin

{{ range service "prowlarr-db" }}
PROWLARR__POSTGRES__HOST={{ .Address }}
PROWLARR__POSTGRES__PORT={{ .Port }}
{{ end }}

PROWLARR__POSTGRES__USER     = {{ key "prowlarr/db/user" }}
PROWLARR__POSTGRES__PASSWORD = {{ key "prowlarr/db/password" }}
PROWLARR__POSTGRES__MAINDB   = {{ key "prowlarr/db/main" }}
PROWLARR__POSTGRES__LOGDB    = {{ key "prowlarr/db/log" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
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
      name = "prowlarr-db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
          "local/init-prowlarr-dbs.sh:/docker-entrypoint-initdb.d/init-prowlarr-dbs.sh:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "prowlarr/db/user" }}
POSTGRES_PASSWORD = {{ key "prowlarr/db/password" }}
POSTGRES_DB       = {{ key "prowlarr/db/main" }}

PROWLARR_MAIN_DB  = {{ key "prowlarr/db/main" }}
PROWLARR_LOG_DB   = {{ key "prowlarr/db/log" }}
EOH
      }

      template {
        destination = "local/init-prowlarr-dbs.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE DATABASE "$PROWLARR_LOG_DB" OWNER "$POSTGRES_USER";
GRANT ALL PRIVILEGES ON DATABASE "$PROWLARR_MAIN_DB" TO "$POSTGRES_USER";
GRANT ALL PRIVILEGES ON DATABASE "$PROWLARR_LOG_DB" TO "$POSTGRES_USER";
EOSQL
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
