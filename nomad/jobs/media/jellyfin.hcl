job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellyfin.local.aydenjahola.com"
  }

  group "jellyfin" {
    count = 1

    network {
      port "http" {
        to = 8096
      }
    }

    service {
      name = "jellyfin"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyfin.entrypoints=https",
        "traefik.http.routers.jellyfin.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$POSTGRES_HOST\" -p \"$POSTGRES_PORT\" -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\"; do echo waiting for jellyfin db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER = {{ key "jellyfin/db/user" }}
POSTGRES_DB   = {{ key "jellyfin/db/name" }}

{{ range service "jellyfin-db" }}
POSTGRES_HOST={{ .Address }}
POSTGRES_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "jellyfin" {
      driver = "docker"

      config {
        image = "ghcr.io/jpvenson/jellyfin.pgsql:10.11.8-1"
        ports = ["http"]

        group_add = ["109", "44"]

        devices = [
          {
            host_path      = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/tv:/data/tvshows:rw",
          "/storage/jellyfin/movies:/data/movies:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true

        data = <<EOH
TZ=Europe/Dublin
JELLYFIN_PublishedServerUrl=https://${NOMAD_META_domain}

POSTGRES_DB       = {{ key "jellyfin/db/name" }}
POSTGRES_USER     = {{ key "jellyfin/db/user" }}
POSTGRES_PASSWORD = {{ key "jellyfin/db/password" }}

{{ range service "jellyfin-db" }}
POSTGRES_HOST={{ .Address }}
POSTGRES_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
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
      name = "jellyfin-db"
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
POSTGRES_USER     = {{ key "jellyfin/db/user" }}
POSTGRES_DB       = {{ key "jellyfin/db/name" }}
POSTGRES_PASSWORD = {{ key "jellyfin/db/password" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
