job "bazarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "bazarr.local.aydenjahola.com"
  }

  group "bazarr" {
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
        to = 6767
      }
    }

    service {
      name = "bazarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.bazarr.entrypoints=https",
        "traefik.http.routers.bazarr.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.bazarr.middlewares=authentik@consulcatalog",
      ]

      check {
        name     = "bazarr-http"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"

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
DB_USER = {{ key "bazarr/db/user" }}
DB_NAME = {{ key "bazarr/db/name" }}
{{ range service "bazarr-db" }}
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

    task "bazarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/bazarr:v1.6.2-ls371"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/movies:/movies:rw",
          "/storage/jellyfin/tv:/tv:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_ENABLED  = true
POSTGRES_USERNAME = {{ key "bazarr/db/user" }}
POSTGRES_PASSWORD = {{ key "bazarr/db/password" }}
POSTGRES_DATABASE = {{ key "bazarr/db/name" }}

{{ range service "bazarr-db" }}
POSTGRES_HOST={{ .Address }}
POSTGRES_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 480
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
      name = "bazarr-db"
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
POSTGRES_USER     = {{ key "bazarr/db/user" }}
POSTGRES_PASSWORD = {{ key "bazarr/db/password" }}
POSTGRES_DB       = {{ key "bazarr/db/name" }}
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
