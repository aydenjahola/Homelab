job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "vault.aydenjahola.com"
  }

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vault.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.vault.entrypoints=https",
      ]
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/vaultwarden:/data:rw",
          "local/.env:/.env"
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOF
ADMIN_TOKEN={{ key "vaultwarden/admin/token" }}
WEBSOCKET_ENABLED=true
SIGNUPS_ALLOWED=false
SMTP_HOST={{ key "vaultwarden/smtp/host" }}
SMTP_FROM={{ key "vaultwarden/smtp/from" }}
SMTP_PORT={{ key "vaultwarden/smtp/port" }}
SMTP_USERNAME={{ key "vaultwarden/smtp/username" }}
SMTP_PASSWORD={{ key "vaultwarden/smtp/password" }}
DOMAIN={{ key "vaultwarden/domain" }}
EOF
      }
    }
  }
}

