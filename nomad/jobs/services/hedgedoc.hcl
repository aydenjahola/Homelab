job "hedgedoc" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "md.aydenjahola.com"
  }

  group "hedgedoc" {
    count = 1

    network {
      port "http" {
        to = 3000
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

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "postgres:13.4-alpine"
        command = "sh"

        args = [
          "-c",
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "hedgedoc/db/user" }}
DB_NAME={{ key "hedgedoc/db/name" }}
{{ range service "hedgedoc-db" }}
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

    task "hedgedoc" {
      driver = "docker"

      config {
        image = "quay.io/hedgedoc/hedgedoc:1.12.0"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/uploads:/hedgedoc/public/uploads:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
CMD_DB_URL                                = postgres://{{ key "hedgedoc/db/user" }}:{{ key "hedgedoc/db/password"}}@{{ range service "hedgedoc-db" }}{{ .Address }}:{{ .Port }}{{ end }}/{{ key "hedgedoc/db/name" }}
CMD_DOMAIN                                = {{ env "NOMAD_META_domain" }}
CMD_PROTOCOL_USESSL                       = {{ key "hedgedoc/ssl" }}
CMD_ALLOW_ANONYMOUS                       = {{ key "hedgedoc/allow/annonymous" }}
CMD_ALLOW_EMAIL_REGISTER                  = false
CMD_EMAIL                                 = false
CMD_OAUTH2_PROVIDERNAME                   = Authentik
CMD_OAUTH2_AUTHORIZATION_URL              = {{ key "authentik/url" }}/application/o/authorize/
CMD_OAUTH2_TOKEN_URL                      = {{ key "authentik/url" }}/application/o/token/
CMD_OAUTH2_USER_PROFILE_URL               = {{ key "authentik/url" }}/application/o/userinfo/
CMD_OAUTH2_USER_PROFILE_ID_ATTR           = preferred_username
CMD_OAUTH2_USER_PROFILE_USERNAME_ATTR     = preferred_username
CMD_OAUTH2_USER_PROFILE_DISPLAY_NAME_ATTR = name
CMD_OAUTH2_USER_PROFILE_EMAIL_ATTR        = email
CMD_OAUTH2_CLIENT_ID                      = {{ key "authentik/oidc/hedgedoc/client_id" }}
CMD_OAUTH2_CLIENT_SECRET                  = {{ key "authentik/oidc/hedgedoc/client_secret" }}
CMD_OAUTH2_SCOPE                          = openid profile email
CMD_ALLOW_GRAVATAR                        = {{ key "hedgedoc/allow/gravatar" }}
CMD_ENABLE_STATS_API                      = false

CMD_SESSION_SECRET                        = {{ key "hedgedoc/session/secret" }}

CMD_PROTOCOL_USESSL                       = true
CMD_URL_ADDPORT                           = false
EOH
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 512
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
      name = "hedgedoc-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
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

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_USER     = {{ key "hedgedoc/db/user" }}
POSTGRES_PASSWORD = {{ key "hedgedoc/db/password" }}
POSTGRES_DB       = {{ key "hedgedoc/db/name" }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 128
        memory_max = 512
      }
    }
  }
}
