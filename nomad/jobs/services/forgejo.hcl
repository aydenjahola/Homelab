job "forgejo" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "git.aydenjahola.com"
  }

  group "forgejo" {
    count = 1

    network {
      port "http" {
        to = 3000
      }

      port "db" {
        to = 5432
      }

      port "redis" {
        to = 6379
      }
    }

    service {
      name = "forgejo"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.forgejo.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.forgejo.entrypoints=https",
      ]
    }

    service {
      name = "forgejo-db"
      port = "db"
    }

    task "forgejo" {
      driver = "docker"

      config {
        image = "codeberg.org/forgejo/forgejo:13"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
          "/etc/timezone:/etc/timezone:ro",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
FORGEJO__DEFAULT__APP_NAME="Homelab Git"

FORGEJO__server__DOMAIN={{ env "NOMAD_META_domain"}}
FORGEJO__server__ROOT_URL=https://{{ env "NOMAD_META_domain" }}

FORGEJO__security__SECRET_KEY={{ key "forgejo/secret/key" }}
FORGEJO__security__GLOBAL_TWO_FACTOR_REQUIREMENT=all

FORGEJO__service__DISABLE_REGISTRATION=true
FORGEJO__service__ENABLE_INTERNAL_SIGNIN=false

FORGEJO__mailer__ENABLED=true
FORGEJO__mailer__PROTOCOL=smtp
FORGEJO__mailer__SMTP_ADDR={{ key "forgejo/smtp/host" }}
FORGEJO__mailer_SMTP_PORT=465
FORGEJO__mailer_USER={{ key "forgejo/smtp/user" }}
FORGEJO__mailer__PASSWD={{ key "forgejo/smtp/password" }}
FORGEJO__mailer__FROM={{ key "forgejo/smtp/from" }}

FORGEJO__database__DB_TYPE=postgres
FORGEJO__database__HOST={{ env "NOMAD_ADDR_db" }}
FORGEJO__database__NAME={{ key "forgejo/db/name" }}
FORGEJO__database__USER={{ key "forgejo/db/user" }}
FORGEJO__database__PASSWD={{ key "forgejo/db/password" }}

FORGEJO__openid__ENABLE_OPENID_SIGNIN=false
FORGEJO__openid__ENABLE_OPENID_SIGNUP=false

FORGEJO__oauth2__ENABLED=true
FORGEJO__oauth2__PROVIDERS__0__NAME=Keycloak
FORGEJO__oauth2__PROVIDERS__0__PROVIDER=openidConnect
FORGEJO__oauth2__PROVIDERS__0__CLIENT_ID={{ key "forgejo/oidc/client/id" }}
FORGEJO__oauth2__PROVIDERS__0__CLIENT_SECRET={{ key "forgejo/oidc/client/secret" }}
FORGEJO__oauth2__PROVIDERS__0__OPENID_CONNECT_AUTO_DISCOVERY_URL={{ key "forgejo/oidc/discovery/url" }}
FORGEJO__oauth2__PROVIDERS__0__SCOPES=openid,profile,email
FORGEJO__oauth2__PROVIDERS__0__AUTO_DISCOVER_URL=true
FORGEJO__oauth2__PROVIDERS__0__ENABLE_AUTO_REGISTER=true
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER={{ key "forgejo/db/user" }}
POSTGRES_PASSWORD={{ key "forgejo/db/password" }}
POSTGRES_DB={{ key "forgejo/db/name" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
