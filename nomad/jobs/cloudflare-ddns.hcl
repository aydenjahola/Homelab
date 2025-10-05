job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "ddns" {
    count = 1

    task "cloudflare-ddns" {
      driver = "docker"

      config {
        image      = "oznu/cloudflare-ddns:latest"
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOF
API_KEY="{{ key "cloudflare/api/key" }}"
ZONE={{ key "cloudflare/zone" }}
SUBDOMAIN={{ key "cloudflare/subdomain" }}
PROXIED=true
EOF
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "25s"
        mode     = "delay"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
