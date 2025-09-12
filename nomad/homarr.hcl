job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "home.aydenjahola.com"
  }

  group "homarr" {
    count = 1

    network {
      port "http" {
        to = 7575
      }
    }

    service {
      name = "homarr"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.homarr.entrypoints=https",
        "traefik.http.routers.homarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "homarr" {
      driver = "docker"

      config {
        image = "ghcr.io/ajnart/homarr:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/configs:/app/data/configs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/icons:/app/public/icons:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data:rw",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
        ]
      }

      template {
        destination  = "local/.env"
        env          = true
        data         = <<EOH
EDIT_MODE_PASSWORD   = {{ key "homarr/edit/password" }}
DISABLE_EDIT_MODE    = {{ key "homarr/edit/disable" }}
DEFAULT_COLOR_SCHEME = {{ key "homarr/default/color" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}

