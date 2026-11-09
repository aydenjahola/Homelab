job "trivy-server" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "trivy.local.aydenjahola.com"
  }

  group "trivy" {
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
        to = 4954
      }
    }

    service {
      name = "trivy-server"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.trivy.entrypoints=https",
        "traefik.http.routers.trivy.rule=Host(`${NOMAD_META_domain}`)",
      ]

      check {
        name     = "trivy-server-http"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "trivy" {
      driver = "docker"

      config {
        # Pinned: v0.69.4–0.69.6 were the malicious releases (CVE-2026-33634). Never use :latest here.
        image = "aquasec/trivy:0.76.1"
        args  = ["server", "--listen", "0.0.0.0:4954", "--cache-dir", "/cache"]
        ports = ["http"]

        readonly_rootfs = true
        cap_drop        = ["all"]
        security_opt    = ["no-new-privileges:true"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/cache:/cache:rw",
        ]
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        change_mode          = "restart"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
TRIVY_TOKEN = {{ key "trivy/server/token" }}
TMPDIR      = /local
EOH
      }

      resources {
        cpu        = 500
        memory     = 64
        memory_max = 1536
      }
    }
  }
}
