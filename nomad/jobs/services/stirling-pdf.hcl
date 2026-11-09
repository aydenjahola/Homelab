job "stirling-pdf" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "pdf.aydenjahola.com"
  }

  group "stirling-pdf" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

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
        image = "docker.stirlingpdf.com/stirlingtools/stirling-pdf:2.5.3-fat"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/trainingData:/usr/share/tessdata:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/extraConfigs:/configs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/customFiles:/customFiles:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/logs:/logs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/pipeline:/pipeline:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DISABLE_ADDITIONAL_FEATURES=false
LANGS=en_GB
SECURITY_ENABLELOGIN=true
EOH
      }

      resources {
        cpu        = 500
        memory     = 800
        memory_max = 1024
      }
    }
  }
}
