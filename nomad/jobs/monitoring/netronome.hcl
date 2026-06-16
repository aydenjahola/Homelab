job "netronome" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "netronome.aydenjahola.com"
  }

  group "netronome" {
    count = 1

    network {
      port "http" {
        to = 7575
      }
    }

    service {
      name = "netronome"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.netronome.entrypoints=https",
        "traefik.http.routers.netronome.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "netronome-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
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
          "until pg_isready -h \"$NETRONOME__DB_HOST\" -p \"$NETRONOME__DB_PORT\" -U \"$NETRONOME__DB_USER\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NETRONOME__DB_USER={{ key "netronome/db/user" }}
{{ range service "netronome-db" }}
NETRONOME__DB_HOST={{ .Address }}
NETRONOME__DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "netronome" {
      driver = "docker"

      config {
        image = "ghcr.io/autobrr/netronome:latest"
        ports = ["http"]

        cap_add = [
          "NET_RAW",
        ]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data/netronome:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NETRONOME__HOST=0.0.0.0
NETRONOME__PORT=7575
NETRONOME__BASE_URL=/

NETRONOME__DB_TYPE=postgres
{{ range service "netronome-db" }}
NETRONOME__DB_HOST={{ .Address }}
NETRONOME__DB_PORT={{ .Port }}
{{ end }}
NETRONOME__DB_USER={{ key "netronome/db/user" }}
NETRONOME__DB_PASSWORD={{ key "netronome/db/password" }}
NETRONOME__DB_NAME={{ key "netronome/db/name" }}
NETRONOME__DB_SSLMODE=disable

NETRONOME__SESSION_SECRET={{ key "netronome/session/secret" }}
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
      name = "netronome-db"
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
POSTGRES_USER     = {{ key "netronome/db/user" }}
POSTGRES_DB       = {{ key "netronome/db/name" }}
POSTGRES_PASSWORD = {{ key "netronome/db/password" }}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
