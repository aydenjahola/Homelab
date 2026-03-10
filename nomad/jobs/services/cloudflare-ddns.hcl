job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "ddns" {
    count = 1

    task "cloudflare-ddns" {
      driver = "docker"

      config {
        image           = "favonia/cloudflare-ddns:latest"
        readonly_rootfs = true
        cap_drop        = ["all"]
        security_opt    = ["no-new-privileges:true"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOF
CLOUDFLARE_API_TOKEN = "{{ key "cloudflare/api/key" }}"
DOMAINS              = {{ key "cloudflare/zone" }}
PROXIED              = true
TZ                   = "Europe/Dublin"
UPDATE_CRON          = "@every 2m"
IP6_PROVIDER         = "none"
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
