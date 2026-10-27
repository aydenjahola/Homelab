job "trivy-server" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "trivy.local.aydenjahola.com"
  }

  group "trivy" {
    count = 1

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
        name     = "trivy-healthz"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"
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
        destination = "secrets/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
TRIVY_TOKEN={{ key "trivy/server/token" }}
TMPDIR=/local
EOH
      }

      resources {
        cpu    = 500
        memory = 1536
      }
    }
  }
}
