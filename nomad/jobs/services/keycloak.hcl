job "keycloak" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "auth.aydenjahola.com"
  }

  group "keycloak" {
    count = 1

    network {
      port "http" {
        to = 8080
      }

      port "db" {
        to = 5432
      }
    }

    service {
      name = "keycloak"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.keycloak.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.keycloak.entrypoints=https",
        "traefik.http.routers.keycloak.tls=true",
        "traefik.http.services.keycloak.loadbalancer.passhostheader=true",
      ]
    }

    service {
      name = "keycloak-db"
      port = "db"
    }

    task "keycloak" {
      driver = "docker"

      config {
        image = "quay.io/keycloak/keycloak:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/opt/keycloak/data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]

        args = ["start"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
KC_HOSTNAME={{ env "NOMAD_META_domain" }}

KC_DB=postgres
KC_DB_URL_HOST={{ env "NOMAD_HOST_IP_db" }}
KC_DB_URL_PORT={{ env "NOMAD_HOST_PORT_db" }}
KC_DB_USERNAME={{ key "keycloak/db/user" }}
KC_DB_PASSWORD={{ key "keycloak/db/password" }}
KC_DB_DATABASE={{ key "keycloak/db/name" }}
KC_DB_SCHEMA=public

KC_METRICS_ENABLED=true
KC_HTTP_ENABLED=true
KC_PROXY_HEADERS=xforwarded
PROXY_ADDRESS_FORWARDING=true
EOH
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
          "local/pg_hba.conf:/var/lib/postgresql/data/pg_hba.conf",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB={{ key "keycloak/db/name" }}
POSTGRES_USER={{ key "keycloak/db/user" }}
POSTGRES_PASSWORD={{ key "keycloak/db/password" }}
EOH
      }

      template {
        destination = "local/pg_hba.conf"
        data        = <<EOH
# Allow local docker network connections for Keycloak
host all all 0.0.0.0/0 md5
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
