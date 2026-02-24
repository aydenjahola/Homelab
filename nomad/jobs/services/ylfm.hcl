job "your-lastfm" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ylfm.local.aydenjahola.com"
  }

  group "your-lastfm" {
    count = 1

    network {
      port "http" {
        to = 1533
      }
    }

    service {
      name = "your-lastfm"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.your-lastfm.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.your-lastfm.entrypoints=https",
      ]
    }

    task "your-lastfm" {
      driver = "docker"

      config {
        image = "gomaink/your-lastfm"
        ports = ["http"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
LASTFM_API_KEY  = {{ key "your-lastfm/api/key" }}
LASTFM_USERNAME = {{ key "your-lastfm/username" }}
EOH
      }

      resources {
        cpu = 300
        memory = 300
      }
    }
  }
}
