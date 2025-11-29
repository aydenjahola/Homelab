job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "traefik.local.aydenjahola.com"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "odin"
  }

  group "traefik" {
    count = 1

    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 8080
      }
    }

    service {
      name = "traefik"
      port = "admin"

      tags = [
          "traefik.enable=true",
          "traefik.http.routers.api.entrypoints=https",
          "traefik.http.routers.api.rule=Host(`${NOMAD_META_domain}`)",
          "traefik.http.routers.api.service=api@internal",
        ]
    }

    task "traefik" {
      driver = "docker"

      config {
        image = "traefik:latest"
        network_mode = "host"

        volumes = [
          "/etc/localtime:/etc/localtime:ro",
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "local/traefik.yml:/traefik.yml:ro",
          "/storage/nomad/${NOMAD_JOB_NAME}/acme.json:/acme.json",
          "/storage/nomad/${NOMAD_JOB_NAME}/traefik_logs:/traefik_logs",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env = true
        data = <<EOH
CF_API_EMAIL={{ key "traefik/cf/email" }}
CF_API_KEY={{ key "traefik/cf/api" }}
EOH
      }

      template {
        destination = "local/traefik.yml"
        data = <<EOH
api:
  dashboard: true

entryPoints:
  http:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: "https"
          scheme: "https"
          permanent: true
  https:
    address: ":443"
    http:
      tls:
        certresolver: cloudflare
        domains:
          - main: "aydenjahola.com"
            sans: "*.aydenjahola.com"
          - main: "local.aydenjahola.com"
            sans: "*.local.aydenjahola.com"
          - main: "inaamessawi.com"
            sans: "*.inaamessawi.com"
          - main: "katyaphone.com.au"
            sans: "*.katyaphone.com.au"

certificatesResolvers:
  cloudflare:
    acme:
      storage: "acme.json"
      dnsChallenge:
        provider: "cloudflare"
        delayBeforeCheck: 90
        disablePropagationCheck: true
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"

providers:
  consulCatalog:
    endpoint:
      address: "127.0.0.1:8500"
      scheme: "http"
    exposedByDefault: false

tracing:
  addInternals: true
  serviceName: traefik

metrics:
  addInternals: true
EOH
      }
    }
  }
}
