job "opengym" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "gym.aydenjahola.com"
  }

  group "opengym" {
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
      mode = "bridge"

      port "http" {
        to = 8080
      }
    }

    service {
      name = "opengym"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.opengym.entrypoints=https,tunnel",
        "traefik.http.routers.opengym.rule=Host(`${NOMAD_META_domain}`)",
      ]

      # Writes and removes a probe file under /data, so it also fails when storage does
      check {
        name     = "api-health"
        type     = "http"
        path     = "/api/health"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "api" {
      driver = "docker"

      config {
        image = "ghcr.io/duartesantos8/opengym-api:1.4.4"

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
        ]
      }

      # TRUST_PROXY (in the template) is safe: the API is only reachable through the web
      # task, which overwrites X-Forwarded-For / X-Real-IP with the real peer.
      env {
        TZ       = "Europe/Dublin"
        PORT     = "3000"
        DATA_DIR = "/data"
      }

      template {
        destination = "local/.env"
        env         = true
        perms       = "0600"
        data        = <<EOH
RP_ID   = {{ env "NOMAD_META_domain" }}
ORIGIN  = https://{{ env "NOMAD_META_domain" }}
RP_NAME = openGym

FIRST_USER_ADMIN = 1
INVITE_ONLY      = {{ keyOrDefault "opengym/invite_only" "1" }}
ALLOW_GUEST      = 0
PASSWORD_LOGIN   = 0
SESSION_DAYS     = 90
TRUST_PROXY      = 1
AUDIT_IP         = off
EOH
      }

      resources {
        cpu        = 100
        memory     = 96
        memory_max = 256
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "ghcr.io/duartesantos8/opengym-web:1.4.4"
        ports = ["http"]
      }

      # nginx renders its config from these at start-up. BACKEND is an IP, so the
      # resolver is never queried (Docker's 127.0.0.11 does not exist in a Nomad bridge).
      env {
        TZ               = "Europe/Dublin"
        NGINX_PORT       = "8080"
        BACKEND          = "127.0.0.1"
        PORT             = "3000"
        RESOLVER         = "127.0.0.1"
        BASE_PATH        = ""
        MEDIA_UPLOAD_MAX = "48m"
        # Cloudflare proxies the zone and sets this header itself, so pass the visitor on
        CF_CONNECTING_IP = "$http_cf_connecting_ip"
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 128
      }
    }
  }
}
