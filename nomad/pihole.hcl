job "pihole" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "pihole.local.aydenjahola.com"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "odin"
  }

  group "pihole" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "dns" {
        static = 53
        to     = 53
      }
    }

    service {
      name = "pihole"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.pihole.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.pihole.entrypoints=https",
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
        memory = 800
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
TZ=Europe/Dublin

FTLCONF_webserver_api_password={{ key "pihole/web/password" }}

FTLCONF_dns_listeningMode= 'all'
EOH
      }
    }
  }
}

