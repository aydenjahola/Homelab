job "uptime-kuma" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "status.aydenjahola.com"
  }

  group "uptime-kuma" {
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
        to = 3001
      }
    }

    service {
      name = "uptime-kuma"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.uptime-kuma.entrypoints=https",
        "traefik.http.routers.uptime-kuma.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:3.19.9"
        command = "sh"

        args = [
          "-c",
          "until nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
{{ range service "uptime-kuma-db" }}
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

    task "uptime-kuma" {
      driver = "docker"

      config {
        image = "louislam/uptime-kuma:2.5.9-slim"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/data:rw",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        change_mode          = "restart"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
UPTIME_KUMA_DB_TYPE = mariadb

{{- range service "uptime-kuma-db" }}
UPTIME_KUMA_DB_HOSTNAME = {{ .Address }}
UPTIME_KUMA_DB_PORT     = {{ .Port }}
{{- end }}

UPTIME_KUMA_DB_NAME     = {{ key "uptime-kuma/db/name" }}
UPTIME_KUMA_DB_USERNAME = {{ key "uptime-kuma/db/user" }}
UPTIME_KUMA_DB_PASSWORD = {{ key "uptime-kuma/db/password" }}
EOH
      }

      resources {
        cpu        = 200
        memory     = 224
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
        to = 3306
      }
    }

    service {
      name = "uptime-kuma-db"
      port = "db"

      check {
        name     = "mariadb-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "300s"
          ignore_warnings = false
        }
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/mariadb:11.8.9-r0-ls239"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config",
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
PUID                = 1000
PGID                = 1000
TZ                  = Europe/Dublin
MYSQL_ROOT_PASSWORD = {{ key "uptime-kuma/db/root/password" }}
MYSQL_DATABASE      = {{ key "uptime-kuma/db/name" }}
MYSQL_USER          = {{ key "uptime-kuma/db/user" }}
MYSQL_PASSWORD      = {{ key "uptime-kuma/db/password" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 384
        memory_max = 512
      }
    }
  }
}
