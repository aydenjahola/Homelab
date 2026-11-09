job "tracearr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "tracearr.local.aydenjahola.com"
  }

  group "tracearr" {
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
        "traefik.http.routers.tracearr.middlewares=authentik@consulcatalog",
      ]

      check {
        name     = "tracearr-http"
        type     = "http"
        path     = "/"
        port     = "http"
        interval = "10s"
        timeout  = "3s"

        check_restart {
          limit           = 3
          grace           = "120s"
          ignore_warnings = false
        }
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER={{ key "tracearr/db/user" }}
DB_NAME={{ key "tracearr/db/name" }}
{{ range service "tracearr-db" }}
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

    task "tracearr" {
      driver = "docker"

      config {
        image = "ghcr.io/connorgallopo/tracearr:3.1.7"
        ports = ["http"]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
NODE_ENV = production
PORT     = 3000
HOST     = 0.0.0.0
TZ       = "Europe/Dublin"

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
        cpu        = 500
        memory     = 288
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

      port "redis" {
        to = 6379
      }
    }

    service {
      name = "tracearr-db"
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

    service {
      name = "tracearr-redis"
      port = "redis"

      check {
        name     = "redis-ready"
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

    task "timescale" {
      driver = "docker"

      config {
        image = "timescale/timescaledb-ha:pg18.1-ts2.25.0"
        ports = ["db"]

        command = "postgres"
        args = [
          "-c", "timescaledb.max_tuples_decompressed_per_dml_transaction=0",
          "-c", "max_locks_per_transaction=4096",
          "-c", "timescaledb.telemetry_level=off",
        ]

        shm_size = 536870912 # 512MB

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/home/postgres/pgdata/data",
        ]

        ulimit {
          nofile = "65536:65536"
        }
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_DB       = {{ key "tracearr/db/name" }}
POSTGRES_USER     = {{ key "tracearr/db/user" }}
POSTGRES_PASSWORD = {{ key "tracearr/db/password" }}
EOH
      }

      resources {
        cpu        = 1000
        memory     = 128
        memory_max = 1024
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image   = "redis:8.10.3-alpine"
        ports   = ["redis"]
        command = "redis-server"
        args    = ["--appendonly", "yes"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data",
        ]
      }

      resources {
        cpu        = 300
        memory     = 64
        memory_max = 256
      }
    }
  }
}
