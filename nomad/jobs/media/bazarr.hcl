job "bazarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "bazarr.local.aydenjahola.com"
  }

  group "bazarr" {
    count = 1

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
      ]

      check {
        name     = "bazarr-http"
        type     = "http"
        path     = "/api/system/status"
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "bazarr/db/user" }}
DB_NAME={{ key "bazarr/db/name" }}
{{ range service "bazarr-db" }}
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

    task "bazarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/bazarr:latest"
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_ENABLED=true
POSTGRES_USERNAME={{ key "bazarr/db/user" }}
POSTGRES_PASSWORD={{ key "bazarr/db/password" }}
POSTGRES_DATABASE={{ key "bazarr/db/name" }}

{{ range service "bazarr-db" }}
POSTGRES_HOST={{ .Address }}
POSTGRES_PORT={{ .Port }}
{{ end }}
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
      name = "bazarr-db"
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
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "bazarr/db/user" }}
POSTGRES_PASSWORD = {{ key "bazarr/db/password" }}
POSTGRES_DB       = {{ key "bazarr/db/name" }}
EOH
      }

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
