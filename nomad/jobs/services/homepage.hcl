job "homepage" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "home.aydenjahola.com"
  }

  group "homepage" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = false
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
        to = 3000
      }
    }

    service {
      name = "homepage"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.homepage.entrypoints=https,tunnel",
        "traefik.http.routers.homepage.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "homepage-http"
        type     = "http"
        path     = "/api/healthcheck"
        interval = "15s"
        timeout  = "3s"

        header {
          Host = ["${NOMAD_META_domain}"]
        }
      }
    }

    task "homepage" {
      driver = "docker"

      config {
        image = "ghcr.io/gethomepage/homepage:v2.8.0"
        ports = ["http"]

        volumes = [
          "local/config:/app/config",
        ]
      }

      env {
        TZ                     = "Europe/Dublin"
        HOMEPAGE_ALLOWED_HOSTS = "${NOMAD_META_domain}"
      }

      dynamic "template" {
        for_each = fileset(".", "jobs/services/homepage/*.yaml")

        content {
          data            = file(template.value)
          destination     = "local/config/${basename(template.value)}"
          left_delimiter  = "[["
          right_delimiter = "]]"
          change_mode     = "restart"
        }
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 384
      }
    }
  }
}
