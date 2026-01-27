job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "grafana.aydenjahola.com"
  }

  group "grafana" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
    }

    service {
      name = "grafana"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.grafana.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.grafana.entrypoints=https"
      ]
    }

    task "grafana" {
      driver = "docker"

      config {
        image = "grafana/grafana:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/grafana",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/grafana/plugins"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
GF_SERVER_ROOT_URL=https://{{ env "NOMAD_META_domain" }}

GF_PLUGINS_PREINSTALL=grafana-clock-panel
GF_USERS_ALLOW_SIGN_UP=false

GF_AUTH_ANONYMOUS_ENABLED=false
GF_AUTH_BASIC_ENABLED=false

GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP=true

GF_AUTH_GENERIC_OAUTH_NAME=Keycloak
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true
GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH=email
GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH=username
GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH=full_name
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=contains(resource_access.grafana.roles[*], 'admin') && 'Admin' || contains(resource_access.grafana.roles[*], 'editor') && 'Editor' || 'Viewer'

GF_AUTH_GENERIC_OAUTH_CLIENT_ID={{ key "grafana/client/id" }}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET={{ key "grafana/client/secret" }}
GF_AUTH_GENERIC_OAUTH_SCOPES="openid profile email offline_access roles"
GF_AUTH_GENERIC_OAUTH_AUTH_URL={{ key "grafana/auth/url" }}
GF_AUTH_GENERIC_OAUTH_TOKEN_URL={{ key "grafana/token/url" }}
GF_AUTH_GENERIC_OAUTH_API_URL={{ key "grafana/userinfo/url" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
