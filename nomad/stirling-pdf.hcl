job "stirling-pdf" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "pdf.aydenjahola.com"
  }

  group "stirling-pdf" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "stirling-pdf"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.stirling.entrypoints=https",
        "traefik.http.routers.stirling.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "stirling-pdf" {
      driver = "docker"

      config {
        image = "docker.stirlingpdf.com/stirlingtools/stirling-pdf:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/trainingData:/usr/share/tessdata:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/extraConfigs:/configs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/customFiles:/customFiles:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/logs:/logs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/pipeline:/pipeline:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
DISABLE_ADDITIONAL_FEATURES=false
LANGS=en_GB
SECURITY_ENABLELOGIN=true
EOH
      }
    }
  }
}

