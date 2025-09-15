job "pihole" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "pihole.local.aydenjahola.com"
  }

  group "pihole" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "dns" {
        static = 53
      }
    }

    service {
      name = "pihole"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.pihole.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.pihole.entrypoints=https",
        "traefik.http.routers.pihole.middlewares=pihole-admin-redirect",
        "traefik.http.middlewares.pihole-admin-redirect.redirectregex.regex=^https?://([^/]+)/?$",
        "traefik.http.middlewares.pihole-admin-redirect.redirectregex.replacement=https://${1}/admin",
        "traefik.http.middlewares.pihole-admin-redirect.redirectregex.permanent=true",
      ]
    }

    task "pihole" {
      driver = "docker"

      config {
        image = "pihole/pihole:latest"
        ports = ["http", "dns"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/etc-pihole:/etc/pihole:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/etc-dnsmasq.d:/etc/dnsmasq.d:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
TZ=Europe/Dublin
WEBPASSWORD={{ key "pihole/web/password" }}
EOH
      }
    }
  }
}

