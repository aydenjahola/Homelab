job "gatus" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "gatus.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 5432
      }
    }

    service {
      name = "gatus-db"
      port = "db"

      check {
        name     = "postgres-tcp"
        type     = "tcp"
        port     = "db"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
POSTGRES_DB       = {{ key "gatus/db/name" }}
POSTGRES_USER     = {{ key "gatus/db/user" }}
POSTGRES_PASSWORD = {{ key "gatus/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }

  group "gatus" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "gatus"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.gatus.entrypoints=https",
        "traefik.http.routers.gatus.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:3.19"
        command = "sh"
        args = [
          "-c",
          "while ! nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo 'Waiting for DB...'; sleep 1; done; echo 'DB is ready!'"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
{{- range service "gatus-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    task "gatus" {
      driver = "docker"

      config {
        image = "twinproduction/gatus:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config",
          "local/config.yaml:/config/config.yaml",
        ]
      }

      template {
        destination = "local/config.yaml"
        data        = <<EOH
ui:
  title: "Homelab Status"
  description: "Status and uptime for my homelab"
  header: "Status"
  dashboard-heading: "Health Dashboard"
  dashboard-subheading: "Centralised dashboard to monitor all my running services and track downtime"
  logo: "https://www.aydenjahola.com/favicon.ico"
  link: "https://{{ env "NOMAD_META_domain" }}"

  dark-mode: on

storage:
  type: postgres
  path: '{{- range service "gatus-db" -}}postgres://{{ key "gatus/db/user" | urlquery }}:{{ key "gatus/db/password" | urlquery }}@{{ .Address }}:{{ .Port }}/{{ key "gatus/db/name" | urlquery }}?sslmode=disable{{- end -}}'

alerting:
  discord:
    webhook-url: '{{ key "gatus/discord/webhook/url" }}'
    default-alert:
      enabled: true
      send-on-resolved: true
      failure-threshold: 3
      success-threshold: 2

defaults: &defaults
  interval: 60s
  alerts:
    - type: discord
  conditions:
    - "[STATUS] == 200"

defaults_https: &defaults_https
  <<: *defaults
  conditions:
    - "[STATUS] == 200"
    - "[CERTIFICATE_EXPIRATION] > 48h"

endpoints:
  # --- Core / Home ---
  - name: homarr
    group: services
    url: "https://home.aydenjahola.com"
    <<: *defaults_https

  - name: home-assistant
    group: services
    url: "https://ha.local.aydenjahola.com"
    <<: *defaults_https

  # --- Analytics / Docs ---
  - name: plausible
    group: services
    url: "https://plausible.aydenjahola.com"
    <<: *defaults_https

  - name: homelab-docs
    group: docs
    url: "https://docs.local.aydenjahola.com"
    <<: *defaults_https

  - name: hedgedoc
    group: sercices
    url: "https://md.aydenjahola.com"
    <<: *defaults_https

  - name: stirling-pdf
    group: sercices
    url: "https://pdf.aydenjahola.com/api/v1/info/status"
    <<: *defaults_https

  # --- Auth / Security ---
  - name: vaultwarden
    group: sercices
    url: "https://vault.aydenjahola.com"
    <<: *defaults_https

  - name: keycloak
    group: services
    url: "https://auth.aydenjahola.com"
    <<: *defaults_https

  # --- Cloud / Apps ---
  - name: nextcloud
    group: services
    url: "https://nextcloud.local.aydenjahola.com"
    <<: *defaults_https

  - name: forgejo
    group: services
    url: "https://git.aydenjahola.com"
    <<: *defaults_https

  # --- Monitoring / Infra ---
  - name: grafana
    group: monitoring
    url: "https://grafana.aydenjahola.com"
    <<: *defaults_https

  - name: prometheus
    group: monitoring
    url: "https://prometheus.local.aydenjahola.com"
    <<: *defaults_https

  - name: traefik
    group: infra
    url: "https://traefik.local.aydenjahola.com"
    <<: *defaults_https

  # --- Media Stack ---
  - name: jellyfin
    group: media
    url: "https://jellyfin.local.aydenjahola.com"
    <<: *defaults_https

  - name: jellyseerr
    group: media
    url: "https://jellyseerr.local.aydenjahola.com"
    <<: *defaults_https

  - name: radarr
    group: media
    url: "https://radarr.local.aydenjahola.com"
    <<: *defaults_https

  - name: sonarr
    group: media
    url: "https://sonarr.local.aydenjahola.com"
    <<: *defaults_https

  - name: prowlarr
    group: media
    url: "https://prowl.local.aydenjahola.com"
    <<: *defaults_https

  - name: jellystat
    group: media
    url: "https://jellystat.local.aydenjahola.com"
    <<: *defaults_https

  - name: flaresolverr
    group: media
    url: "https://flaresolverr.local.aydenjahola.com"
    <<: *defaults_https

  # --- Nomad Boxes ---
  - name: nomad-odin
    group: nomad
    url: "http://192.168.1.100:4646"
    <<: *defaults

  - name: nomad-thor
    group: nomad
    url: "http://192.168.1.101:4646"
    <<: *defaults

  - name: nomad-loki
    group: nomad
    url: "http://192.168.1.102:4646"
    <<: *defaults

  # --- Public sites ---
  - name: main-website
    group: public
    url: "https://aydenjahola.com"
    <<: *defaults_https

  - name: blog
    group: public
    url: "https://blog.aydenjahola.com"
    <<: *defaults_https

  - name: solar-racing
    group: public
    url: "https://solarracing.ie"
    <<: *defaults_https

  - name: katyaphone
    group: public
    url: "https://katyaphone.com.au"
    <<: *defaults_https

  - name: inaamessawi
    group: public
    url: "https://inaamessawi.com"
    <<: *defaults_https
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
