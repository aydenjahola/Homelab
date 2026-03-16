job "tracearr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "tracearr.local.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 5432
      }

      port "redis" {
        to = 6379
      }
    }

    service {
      name = "tracearr-db"
      port = "db"

      check {
        name     = "postgres-tcp"
        type     = "tcp"
        port     = "db"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "tracearr-redis"
      port = "redis"

      check {
        name     = "redis-tcp"
        type     = "tcp"
        port     = "redis"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "timescale" {
      driver = "docker"

      config {
        image   = "timescale/timescaledb-ha:pg18.1-ts2.25.0"
        ports   = ["db"]

        command = "postgres"
        args = [
          "-c", "timescaledb.max_tuples_decompressed_per_dml_transaction=0",
          "-c", "max_locks_per_transaction=4096",
          "-c", "timescaledb.telemetry_level=off",
        ]

        shm_size = 536870912 # 512MB

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/home/postgres/pgdata/data"
        ]

        ulimit {
          nofile = "65536:65536"
        }
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "tracearr/db/name" }}
POSTGRES_USER     = {{ key "tracearr/db/user" }}
POSTGRES_PASSWORD = {{ key "tracearr/db/password" }}
EOH
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image   = "redis:8-alpine"
        ports   = ["redis"]
        command = "redis-server"
        args    = ["--appendonly", "yes"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data"
        ]
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }

  group "tracearr" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
    }

    service {
      name = "tracearr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.tracearr.entrypoints=https",
        "traefik.http.routers.tracearr.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "tracearr-http"
        type     = "http"
        path     = "/"
        port     = "http"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:3.19"
        command = "sh"
        args = [
          "-c",
          "while ! nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo 'Waiting for Postgres...'; sleep 1; done; echo 'DB is ready!'"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{- range service "tracearr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    task "tracearr" {
      driver = "docker"

      config {
        image = "ghcr.io/connorgallopo/tracearr:latest"
        ports = ["http"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
TZ="Eurple/Dublin"

{{- range service "tracearr-db" }}
DATABASE_URL=postgres://{{ key "tracearr/db/user" }}:{{ key "tracearr/db/password" }}@{{ .Address }}:{{ .Port }}/{{ key "tracearr/db/name" }}
{{- end }}

{{- range service "tracearr-redis" }}
REDIS_URL=redis://{{ .Address }}:{{ .Port }}
{{- end }}

JWT_SECRET    = {{ key "tracearr/app/jwt/secret" }}
COOKIE_SECRET = {{ key "tracearr/app/cookie/secret" }}
CORS_ORIGIN   = {{ env "NOMAD_META_domain" }}
LOG_LEVEL     = info 
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
