job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "home.aydenjahola.com"
  }

  group "homarr" {
    count = 1

    network {
      port "http" {
        to = 7575
      }

      port "db" {
        to = 5432
      }

      port "redis" {
        to = 6379
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
        destination    = "local/.env"
        env            = true
        data           = <<EOH
EDIT_MODE_PASSWORD     = {{ key "homarr/edit/password" }}
DISABLE_EDIT_MODE      = {{ key "homarr/edit/disable" }}
DEFAULT_COLOR_SCHEME   = {{ key "homarr/default/color" }}
SECRET_ENCRYPTION_KEY  = {{ key "homarr/encryption/key" }}

DB_DRIVER              = {{ key "homarr/db/driver" }}
DB_DIALECT             = {{ key "homarr/db/dialect" }}
DB_HOST                = {{ env "NOMAD_HOST_IP_db" }}
DB_PORT                = {{ env "NOMAD_HOST_PORT_db" }}
DB_NAME                = {{ key "homarr/db/name" }}
DB_USER                = {{ key "homarr/db/user" }}
DB_PASSWORD            = {{ key "homarr/db/password" }}

REDIS_IS_EXTERNAL      = true
REDIS_HOST             = {{ env "NOMAD_HOST_IP_redis" }}
REDIS_PORT             = {{ env "NOMAD_HOST_PORT_redis" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 800
      }
    }

    service {
      name = "homarr-db"
      port = "db"
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
        data = <<EOH
POSTGRES_USER={{ key "homarr/db/user" }}
POSTGRES_NAME={{ key "homarr/db/name" }}
POSTGRES_PASSWORD={{ key "homarr/db/password" }}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
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
