job "linkwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "links.aydenjahola.com"
  }

  group "linkwarden" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
      port "db" {
        to = 5432
      }
      port "search" {
        to = 7700
      }
    }

    service {
      name = "linkwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.links.entrypoints=https",
        "traefik.http.routers.link.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "linkwarden" {
      driver = "docker"

      config {
        image = "ghcr.io/linkwarden/linkwarden:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data/data:rw",
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NEXTAUTH_URL=http://{{ env "NOMAD_META_domain" }}/api/v1/auth
NEXTAUTH_SECRET={{ key "linkwarden/nextauth/secret" }}

DATABASE_URL=postgresql://{{ key "linkwarden/db/user" }}:{{ key "linkwarden/db/password" }}@{{ env "NOMAD_ADDR_db" }}/{{ key "linkwarden/db/name" }}

# Additional Optional Settings
NEXT_PUBLIC_DISABLE_REGISTRATION=true
NEXT_PUBLIC_CREDENTIALS_ENABLED=true

# MeiliSearch Settings
MEILI_HOST={{ env "NOMAD_ADDR_search" }}
MEILI_MASTER_KEY={{ key "linkwarden/search/key" }}

# SMTP Settings
NEXT_PUBLIC_EMAIL_PROVIDER=true
EMAIL_FROM={{ key "linkwarden/smtp/from" }}
EMAIL_SERVER=smtp://{{ key "linkwarden/smtp/user" }}:{{ key "linkwarden/smtp/password" }}@{{ key "linkwarden/smtp/host" }}:{{ key "linkwarden/smtp/port" }}
EOH
      }
    }

    service {
      name = "linkwarden-db"
      port = "db"
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:16-alpine"
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
        data        = <<EOH
POSTGRES_USER={{ key "linkwarden/db/user" }}
POSTGRES_PASSWORD={{ key "linkwarden/db/password" }}
POSTGRES_DB={{ key "linkwarden/db/name" }}
EOH
      }
    }
 
    task "meilisearch" {
      driver = "docker"

      config {
        image = "getmeili/meilisearch:v1.12.8"
        ports = ["search"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/meili_data:/meili_data:rw",
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
MEILI_MASTER_KEY={{ key "linkwarden/search/key" }}
EOH
      }
    }
  }
}
