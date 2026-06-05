job "seerr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "seerr.local.aydenjahola.com"
  }

  group "seerr" {
    count = 1

    network {
      port "http" {
        to = 5055
      }
    }

    service {
      name = "seerr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.seerr.entrypoints=https",
        "traefik.http.routers.seerr.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for seerr db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER = {{ key "seerr/db/user" }}
DB_NAME = {{ key "seerr/db/name" }}

{{ range service "seerr-db" }}
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

    task "seerr" {
      driver = "docker"

      config {
        image = "ghcr.io/seerr-team/seerr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/config:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
LOG_LEVEL=debug
TZ=Europe/Dublin

DB_TYPE = postgres
DB_USER = {{ key "seerr/db/user" }}
DB_PASS = {{ key "seerr/db/password" }}
DB_NAME = {{ key "seerr/db/name" }}
DB_POOL_SIZE=10
DB_LOG_QUERIES=false

{{ range service "seerr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 300
        memory = 900
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
      name = "seerr-db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "seerr/db/user" }}
POSTGRES_DB       = {{ key "seerr/db/name" }}
POSTGRES_PASSWORD = {{ key "seerr/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
