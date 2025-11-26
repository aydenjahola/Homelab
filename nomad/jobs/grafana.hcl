job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "grafana.local.aydenjahola.com"
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
GF_PLUGINS_PREINSTALL=grafana-clock-panel
GF_USERS_ALLOW_SIGN_UP=false
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
