job "dozzle" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "dozzle.local.aydenjahola.com"
  }

  group "dozzle" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "dozzle"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dozzle.entrypoints=https",
        "traefik.http.routers.dozzle.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.dozzle.middlewares=authentik@consulcatalog",
      ]

      check {
        name     = "dozzle-http"
        type     = "http"
        path     = "/healthcheck"
        port     = "http"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "dozzle" {
      driver = "docker"

      config {
        image = "amir20/dozzle:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
DOZZLE_HOSTNAME=nomad-cluster
DOZZLE_REMOTE_AGENT={{- $first := true -}}{{- range service "dozzle-agent" -}}{{- if not $first }},{{ end -}}{{ .Address }}:{{ .Port }}|{{ .Node }}|Nomad{{- $first = false -}}{{- end }}

DOZZLE_AUTH_PROVIDER=forward-proxy
DOZZLE_AUTH_HEADER_USER=X-Authentik-Username
DOZZLE_AUTH_HEADER_EMAIL=X-Authentik-Email
DOZZLE_AUTH_HEADER_NAME=X-Authentik-Name
DOZZLE_AUTH_LOGOUT_URL=https://{{ env "NOMAD_META_domain" }}/outpost.goauthentik.io/sign_out
EOH
      }

      resources {
        cpu        = 200
        memory     = 96
        memory_max = 256
      }
    }
  }
}
