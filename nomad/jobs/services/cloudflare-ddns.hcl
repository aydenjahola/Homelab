job "cloudflare-ddns" {
  datacenters = ["dc1"]
  type        = "service"

  group "ddns" {
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

    task "cloudflare-ddns" {
      driver = "docker"

      config {
        image           = "favonia/cloudflare-ddns:1.18.0"
        readonly_rootfs = true
        cap_drop        = ["all"]
        security_opt    = ["no-new-privileges:true"]
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
CLOUDFLARE_API_TOKEN = "{{ key "cloudflare/api/key" }}"
DOMAINS              = {{ key "cloudflare/zone" }}
PROXIED              = true
TZ                   = "Europe/Dublin"
UPDATE_CRON          = "@every 2m"
IP6_PROVIDER         = "none"
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "25s"
        mode     = "delay"
      }
    }
  }
}
