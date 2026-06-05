job "sonarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sonarr.local.aydenjahola.com"
  }

  group "sonarr" {
    count = 1

    network {
      port "http" {
        to = 8989
      }
    }

    service {
      name = "sonarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.sonarr.entrypoints=https",
        "traefik.http.routers.sonarr.rule=Host(`${NOMAD_META_domain}`)"
      ]

      check {
        name     = "sonarr-http"
        type     = "http"
        path     = "/ping"
        interval = "30s"
        timeout  = "5s"
      }
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "sonarr/db/user" }}
DB_MAIN={{ key "sonarr/db/main" }}
{{ range service "sonarr-db" }}
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

    task "sonarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/sonarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/tv:/tv:rw",
          "/storage/jellyfin/downloads:/downloads:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
SONARR__POSTGRES__HOST     = {{ range service "sonarr-db" }}{{ .Address }}{{ end }}
SONARR__POSTGRES__PORT     = {{ range service "sonarr-db" }}{{ .Port }}{{ end }}
SONARR__POSTGRES__USER     = {{ key "sonarr/db/user" }}
SONARR__POSTGRES__PASSWORD = {{ key "sonarr/db/password" }}
SONARR__POSTGRES__MAINDB   = {{ key "sonarr/db/main" }}
SONARR__POSTGRES__LOGDB    = {{ key "sonarr/db/log" }}
EOH
      }

      resources {
        cpu    = 1000
        memory = 1024
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
      name = "sonarr-db"
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
          "local/init-sonarr-dbs.sh:/docker-entrypoint-initdb.d/init-sonarr-dbs.sh:ro",
        ]
      }

      template {
        destination = "local/init-sonarr-dbs.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE DATABASE "{{ key "sonarr/db/log" }}" OWNER "{{ key "sonarr/db/user" }}";
EOSQL
EOH
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "sonarr/db/user" }}
POSTGRES_PASSWORD = {{ key "sonarr/db/password" }}
POSTGRES_DB       = {{ key "sonarr/db/main" }}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
