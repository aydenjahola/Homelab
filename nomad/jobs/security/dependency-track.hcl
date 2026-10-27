job "dependency-track" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "dtrack.local.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 5432
      }
    }

    service {
      name = "dependency-track-db"
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
        image        = "postgres:18-alpine"
        ports        = ["db"]
        security_opt = ["no-new-privileges:true"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB={{ key "dependency-track/db/name" }}
POSTGRES_USER={{ key "dependency-track/db/user" }}
POSTGRES_PASSWORD={{ key "dependency-track/db/password" }}
TZ=Europe/Dublin
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }

  group "dependency-track" {
    count = 1

    network {
      port "api" {
        to = 8080
      }
      port "health" {
        to = 9000
      }
      port "web" {
        to = 8080
      }
    }

    service {
      name = "dependency-track-api"
      port = "api"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dtrack-api.entrypoints=https",
        "traefik.http.routers.dtrack-api.rule=Host(`${NOMAD_META_domain}`) && PathPrefix(`/api`)",
      ]

      check {
        name     = "dtrack-ready"
        type     = "http"
        port     = "health"
        path     = "/health/ready"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name = "dependency-track"
      port = "web"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dtrack.entrypoints=https",
        "traefik.http.routers.dtrack.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:3.22"
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
{{- range service "dependency-track-db" }}
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

    task "apiserver" {
      driver = "docker"
      user   = "1000:1000"

      config {
        image        = "ghcr.io/dependencytrack/apiserver:5.2.1"
        ports        = ["api", "health"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges:true"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{- range service "dependency-track-db" }}
DT_DATASOURCE_URL=jdbc:postgresql://{{ .Address }}:{{ .Port }}/{{ key "dependency-track/db/name" }}
{{- end }}
DT_DATASOURCE_USERNAME={{ key "dependency-track/db/user" }}
DT_DATASOURCE_PASSWORD={{ key "dependency-track/db/password" }}

DT_OUTBOUND_ALLOWED_DESTINATIONS=external,trivy.local.aydenjahola.com

TZ=Europe/Dublin
EOH
      }

      resources {
        cpu    = 1500
        memory = 3072
      }
    }

    task "frontend" {
      driver = "docker"

      config {
        image        = "ghcr.io/dependencytrack/frontend:5.2.1"
        ports        = ["web"]
        cap_drop     = ["all"]
        security_opt = ["no-new-privileges:true"]
      }

      env = {
        "API_BASE_URL" = "https://${NOMAD_META_domain}"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
