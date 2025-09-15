job "hedgedoc" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "md.aydenjahola.com"
  }

  group "hedgedoc" {
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
      name = "hedgedoc"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.md.entrypoints=https",
        "traefik.http.routers.md.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "hedgedoc" {
      driver = "docker"

      config {
        image = "quay.io/hedgedoc/hedgedoc"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/uploads:/hedgedoc/public/uploads:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
CMD_DB_URL=postgres://{{ key "hedgedoc/db/user" }}:{{ key "hedgedoc/db/password"}}@{{ env "NOMAD_ADDR_db" }}/{{ key "hedgedoc/db/name" }}
CMD_DOMAIN={{ env "NOMAD_META_domain" }}
CMD_PROTOCOL_USESSL={{ key "hedgedoc/ssl" }}
CMD_ALLOW_ANONYMOUS={{ key "hedgedoc/allow/annonymous" }}
CMD_ALLOW_EMAIL_REGISTER={{ key "hedgedoc/allow/email" }}
CMD_ALLOW_GRAVATAR={{ key "hedgedoc/allow/gravatar" }}
EOH
      }
    }

    service {
      name = "hedgedoc-db"
      port = "db"
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:13.4-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/db:/var/lib/postgresql/data:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
POSTGRES_USER={{ key "hedgedoc/db/user" }}
POSTGRES_PASSWORD={{ key "hedgedoc/db/password" }}
POSTGRES_DB={{ key "hedgedoc/db/name" }}
EOH
      }
    }
  }
}

