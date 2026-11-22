job "cloudflared" {
  datacenters = ["dc1"]
  type        = "system"

  # Cloudflare Tunnel connector, one per node so the tunnel survives a node
  # going down. The tunnel, its ingress rule and the token are managed by
  # OpenTofu (cloudflare/tunnel.tf). All traffic goes to Traefik's loopback
  # "tunnel" entrypoint on the same node.

  group "cloudflared" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "metrics" {}
    }

    service {
      name = "cloudflared-metrics"
      port = "metrics"

      check {
        name     = "cloudflared-ready"
        type     = "http"
        path     = "/ready"
        interval = "15s"
        timeout  = "3s"

        check_restart {
          limit = 3
          grace = "2m"
        }
      }
    }

    task "cloudflared" {
      driver = "docker"

      config {
        image           = "cloudflare/cloudflared:2026.11.1"
        network_mode    = "host"
        readonly_rootfs = true
        cap_drop        = ["all"]
        security_opt    = ["no-new-privileges:true"]

        args = [
          "tunnel",
          "--no-autoupdate",
          "--metrics", "${NOMAD_IP_metrics}:${NOMAD_PORT_metrics}",
          "run",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
TUNNEL_TOKEN = {{ key "cloudflare/tunnel/token" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 256
      }
    }
  }
}
