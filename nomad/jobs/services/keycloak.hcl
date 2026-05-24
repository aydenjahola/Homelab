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
          "until pg_isready -h \"$KC_DB_URL_HOST\" -p \"$KC_DB_URL_PORT\" -U \"$KC_DB_USERNAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
KC_DB_USERNAME={{ key "keycloak/db/user" }}
{{ range service "keycloak-db" }}
KC_DB_URL_HOST={{ .Address }}
KC_DB_URL_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
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
KC_HOSTNAME              ={{ env "NOMAD_META_domain" }}

KC_DB=postgres
KC_DB_USERNAME           = {{ key "keycloak/db/user" }}
KC_DB_PASSWORD           = {{ key "keycloak/db/password" }}
KC_DB_DATABASE           = {{ key "keycloak/db/name" }}
KC_DB_SCHEMA             = public

{{ range service "keycloak-db" }}
KC_DB_URL_HOST={{ .Address }}
KC_DB_URL_PORT={{ .Port }}
{{ end }}

KC_METRICS_ENABLED       = true
KC_HTTP_ENABLED          = true
KC_PROXY_HEADERS         = xforwarded
PROXY_ADDRESS_FORWARDING = true
EOH
      }

      resources {
        cpu    = 1000
        memory = 2048
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
      name = "keycloak-db"
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
          "local/pg_hba.conf:/var/lib/postgresql/data/pg_hba.conf",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "keycloak/db/name" }}
POSTGRES_USER     = {{ key "keycloak/db/user" }}
POSTGRES_PASSWORD = {{ key "keycloak/db/password" }}
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
