job "nextcloud" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "nextcloud.local.aydenjahola.com"
  }

  group "nextcloud" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "nextcloud"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nextcloud.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.nextcloud.entrypoints=https",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "nextcloud:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/www/html:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_HOST={{ env "NOMAD_ADDR_db" }}
POSTGRES_DB={{ key "nextcloud/db/name" }}
POSTGRES_USER={{ key "nextcloud/db/user" }}
POSTGRES_PASSWORD={{ key "nextcloud/db/password" }}
EOH
      }
    }

    service {
      name = "nextcloud-db"
      port = "db"
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB={{ key "nextcloud/db/name" }}
POSTGRES_USER={{ key "nextcloud/db/user" }}
POSTGRES_PASSWORD={{ key "nextcloud/db/password" }}
EOH
      }
    }

    task "cron" {
      driver = "docker"

      config {
        image = "nextcloud:latest"

        volumes = [
          "/storage/nomad/nextcloud/app:/var/www/html:rw",
          "/etc/localtime:/etc/localtime:ro"
        ]

        entrypoint = [ "/cron.sh" ]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_HOST={{ env "NOMAD_ADDR_db" }}
POSTGRES_DB={{ key "nextcloud/db/name" }}
POSTGRES_USER={{ key "nextcloud/db/user" }}
POSTGRES_PASSWORD={{ key "nextcloud/db/password" }}
EOH
      }
    }
  }
}
