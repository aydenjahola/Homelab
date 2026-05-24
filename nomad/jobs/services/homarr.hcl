job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "home.aydenjahola.com"
  }

  group "homarr" {
    count = 1

    network {
      port "http" {
        to = 7575
      }
    }

    service {
      name = "homarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.homarr.entrypoints=https",
        "traefik.http.routers.homarr.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "homarr/db/user" }}
{{ range service "homarr-db" }}
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

    task "homarr" {
      driver = "docker"

      config {
        image = "ghcr.io/homarr-labs/homarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/configs:/app/data/configs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/icons:/app/public/icons:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/appdata:rw",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
EDIT_MODE_PASSWORD    = {{ key "homarr/edit/password" }}
DISABLE_EDIT_MODE     = {{ key "homarr/edit/disable" }}
DEFAULT_COLOR_SCHEME  = {{ key "homarr/default/color" }}
SECRET_ENCRYPTION_KEY = {{ key "homarr/encryption/key" }}

DB_DRIVER             = {{ key "homarr/db/driver" }}
DB_DIALECT            = {{ key "homarr/db/dialect" }}

{{ range service "homarr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}

DB_NAME               = {{ key "homarr/db/name" }}
DB_USER               = {{ key "homarr/db/user" }}
DB_PASSWORD           = {{ key "homarr/db/password" }}

REDIS_IS_EXTERNAL     = true

{{ range service "homarr-redis" }}
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
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
      name = "homarr-db"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "homarr/db/user" }}
POSTGRES_DB       = {{ key "homarr/db/name" }}
POSTGRES_PASSWORD = {{ key "homarr/db/password" }}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }

  group "redis" {
    count = 1

    network {
      port "redis" {
        to = 6379
      }
    }

    service {
      name = "homarr-redis"
      port = "redis"

      check {
        name     = "redis-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "redis:8-alpine"
        ports = ["redis"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
