job "ntfy" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ntfy.aydenjahola.com"
  }

  group "ntfy" {
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
      port "http" {
        to = 80
      }
    }

    service {
      name = "ntfy"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ntfy.entrypoints=https",
        "traefik.http.routers.ntfy.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "ntfy-health"
        type     = "http"
        path     = "/v1/health"
        interval = "15s"
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
DB_USER = {{ key "ntfy/db/user" }}
DB_NAME = {{ key "ntfy/db/name" }}
{{ range service "ntfy-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 50
        memory     = 64
        memory_max = 128
      }
    }

    task "ntfy" {
      driver = "docker"

      config {
        image = "binwiederhier/ntfy:v2.38.1"
        ports = ["http"]
        args  = ["serve", "--config", "/local/server.yml"]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/server.yml"
        perms                = "0600"
        error_on_missing_key = true
        change_mode          = "restart"
        data                 = <<EOH
base-url: "https://{{ env "NOMAD_META_domain" }}"
listen-http: ":80"
behind-proxy: true

database-url: "postgres://{{ key "ntfy/db/user" | urlquery }}:{{ key "ntfy/db/password" | urlquery }}@{{ range service "ntfy-db" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "ntfy/db/name" | urlquery }}?sslmode=disable"
cache-duration: "72h"

auth-default-access: "deny-all"
auth-users:
  - "{{ key "ntfy/admin/user" }}:{{ key "ntfy/admin/hash" }}:admin"
  - "homelab:{{ key "ntfy/publisher/hash" }}:user"
auth-access:
  - "homelab:homelab-*:wo"
auth-tokens:
  - "homelab:{{ key "ntfy/token/grafana" }}:grafana"
  - "homelab:{{ key "ntfy/token/gatus" }}:gatus"
  - "homelab:{{ key "ntfy/token/diun" }}:diun"
  - "homelab:{{ key "ntfy/token/backups" }}:backups"
  - "homelab:{{ key "ntfy/token/cve-scan" }}:cve-scan"

enable-login: true
require-login: true
enable-signup: false

upstream-base-url: "https://ntfy.sh"

log-level: info
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 256
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
      name = "ntfy-db"
      port = "db"

      check {
        name     = "postgres-ready"
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

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/db-pg17:/var/lib/postgresql/data:rw",
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
POSTGRES_USER     = {{ key "ntfy/db/user" }}
POSTGRES_PASSWORD = {{ key "ntfy/db/password" }}
POSTGRES_DB       = {{ key "ntfy/db/name" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 256
      }
    }
  }
}
