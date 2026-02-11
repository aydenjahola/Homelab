job "uptime-kuma" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "status.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 3306
      }
    }

    service {
      name = "uptime-kuma-db"
      port = "db"

      check {
        name     = "mariadb-tcp"
        type     = "tcp"
        port     = "db"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/mariadb:latest"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
PUID=1000
PGID=1000
TZ=Etc/UTC
MYSQL_ROOT_PASSWORD={{ key "uptime-kuma/db/root/password" }}
MYSQL_DATABASE={{ key "uptime-kuma/db/name" }}
MYSQL_USER={{ key "uptime-kuma/db/user" }}
MYSQL_PASSWORD={{ key "uptime-kuma/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }

  group "uptime-kuma" {
    count = 1

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
        image   = "alpine:3.19"
        command = "sh"
        args = [
          "-c",
           "while ! nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo 'Waiting for DB...'; sleep 1; done; echo 'DB is ready!'"
        ]
      }

      template {
        destination = "local/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{- range service "uptime-kuma-db" }}
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

    task "uptime-kuma" {
      driver = "docker"

      config {
        image = "louislam/uptime-kuma:next-slim"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/data:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
UPTIME_KUMA_DB_TYPE     = mariadb

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
        cpu    = 500
        memory = 512
      }
    }
  }
}
