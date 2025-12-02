job "jellystat" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellystat.local.aydenjahola.com"
  }

  group "jellystat" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "jellystat"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellystat.entrypoints=https",
        "traefik.http.routers.jellystat.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "app" {
      driver = "docker"

      config {
        image = "cyfershepard/jellystat:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/backup:/app/backend/backup-data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER={{ key "jellystats/db/user" }}
POSTGRES_PASSWORD={{ key "jellystats/db/password" }}
POSTGRES_IP={{ env "NOMAD_IP_db" }}
POSTGRES_PORT={{ env "NOMAD_HOST_PORT_db" }}

JWT_SECRET={{ key "jellystats/jwt/secret" }}

TZ=Europe/Dublin
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }
    }

    service {
      name = "jellystat-db"
      port = "db"
    }

    task "db" {
      driver = "docker"

      config {
        image   = "postgres:17"
        ports   = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/db:/var/lib/postgresql/data:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER={{ key "jellystats/db/user" }}
POSTGRES_PASSWORD={{ key "jellystats/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }
    }
  }
}
