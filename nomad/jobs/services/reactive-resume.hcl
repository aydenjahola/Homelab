job "reactive-resume" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "resume.local.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 5432
      }
    }

    service {
      name = "reactive-resume-db"
      port = "db"

      check {
        name     = "postgres-tcp"
        type     = "tcp"
        port     = "db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "reactive-resume/db/name" }}
POSTGRES_USER     = {{ key "reactive-resume/db/user" }}
POSTGRES_PASSWORD = {{ key "reactive-resume/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }

  group "reactive-resume" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
    }

    service {
      name = "reactive-resume"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.reactive-resume.entrypoints=https",
        "traefik.http.routers.reactive-resume.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "reactive-resume-http"
        type     = "http"
        path     = "/api/health"
        port     = "http"
        interval = "30s"
        timeout  = "10s"
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
          "while ! nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo 'Waiting for DB...'; sleep 1; done; echo 'DB is ready!'"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
{{- range service "reactive-resume-db" }}
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

    task "reactive-resume" {
      driver = "docker"

      config {
        image = "ghcr.io/amruthpillai/reactive-resume:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
TZ=Europe/Dublin
NODE_ENV=production

APP_URL=https://{{ env "NOMAD_META_domain" }}

AUTH_SECRET={{ key "reactive-resume/auth/secret" }}

DATABASE_URL={{- range service "reactive-resume-db" -}}postgresql://{{ key "reactive-resume/db/user" | urlquery }}:{{ key "reactive-resume/db/password" | urlquery }}@{{ .Address }}:{{ .Port }}/{{ key "reactive-resume/db/name" | urlquery }}{{- end }}

FLAG_DISABLE_SIGNUPS=true

SMTP_HOST   = {{ key "reactive-resume/smtp/host" }}
SMTP_PORT   = 465
SMTP_USER   = {{ key "reactive-resume/smtp/user" }}
SMTP_PASS   = {{ key "reactive-resume/smtp/password" }}
SMTP_FROM   = Reactive Resume <no-reply@aydenjahola.com>
SMTP_SECURE = true
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
