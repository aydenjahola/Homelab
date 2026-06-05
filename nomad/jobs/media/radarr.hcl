job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "radarr.local.aydenjahola.com"
  }

  group "radarr" {
    count = 1

    network {
      port "http" {
        to = 7878
      }
    }

    service {
      name = "radarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.radarr.entrypoints=https",
        "traefik.http.routers.radarr.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "radarr-http"
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
DB_USER={{ key "radarr/db/user" }}
DB_MAIN={{ key "radarr/db/main" }}
{{ range service "radarr-db" }}
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

    task "radarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/radarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/config:rw",
          "/storage/jellyfin/movies:/movies:rw",
          "/storage/jellyfin/downloads:/downloads:rw",
          "/etc/localtime:/etc/localtime:ro",
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
RADARR__POSTGRES__HOST={{ range service "radarr-db" }}{{ .Address }}{{ end }}
RADARR__POSTGRES__PORT={{ range service "radarr-db" }}{{ .Port }}{{ end }}
RADARR__POSTGRES__USER={{ key "radarr/db/user" }}
RADARR__POSTGRES__PASSWORD = {{ key "radarr/db/password" }}
RADARR__POSTGRES__MAINDB   = {{ key "radarr/db/main" }}
RADARR__POSTGRES__LOGDB    = {{ key "radarr/db/log" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 512
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
      name = "radarr-db"
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

      template {
        destination = "local/init-radarr-dbs.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE DATABASE "{{ key "radarr/db/log" }}" OWNER "{{ key "radarr/db/user" }}";
EOSQL
EOH
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "radarr/db/user" }}
POSTGRES_PASSWORD = {{ key "radarr/db/password" }}
POSTGRES_DB       = {{ key "radarr/db/main" }}
EOH
      }

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
          "local/init-radarr-dbs.sh:/docker-entrypoint-initdb.d/init-radarr-dbs.sh:ro",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
