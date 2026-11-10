job "gatus" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "gatus.aydenjahola.com"
  }

  group "gatus" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
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
        image   = "postgres:17-alpine"
        command = "sh"

        args = [
          "-c",
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "gatus/db/user" }}
DB_NAME = {{ key "gatus/db/name" }}
{{ range service "gatus-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
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
        image = "twinproduction/gatus:v5.38.0"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config",
          "local/config.yaml:/config/config.yaml",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/config.yaml"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
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

# Forward-auth apps: Traefik + Authentik answer with a redirect to the login page.
defaults_sso: &defaults_sso
  <<: *defaults
  client:
    ignore-redirect: true
  conditions:
    - "[STATUS] == 302"
    - "[CERTIFICATE_EXPIRATION] > 48h"

endpoints:
  # --- Core / Home ---
  - name: homarr
    group: services
    url: "https://home.aydenjahola.com"
    <<: *defaults_https

  - name: authentik
    group: services
    url: "{{ key "authentik/url" }}/-/health/live/"
    <<: *defaults
    conditions:
      - "[STATUS] < 300"
      - "[CERTIFICATE_EXPIRATION] > 48h"

  - name: archisteamfarm
    group: services
    url: "https://asf.local.aydenjahola.com"
    <<: *defaults_sso

  - name: dozzle
    group: services
    url: "https://dozzle.local.aydenjahola.com"
    <<: *defaults_sso

  - name: watchyourlan
    group: services
    url: "https://wyl.local.aydenjahola.com"
    <<: *defaults_sso

  # --- Analytics / Docs ---
  - name: plausible
    group: services
    url: "https://plausible.aydenjahola.com"
    <<: *defaults_https

  - name: homelab-docs
    group: docs
    url: "https://docs.local.aydenjahola.com"
    <<: *defaults_sso

  - name: hedgedoc
    group: services
    url: "https://md.aydenjahola.com"
    <<: *defaults_https

  - name: stirling-pdf
    group: services
    url: "https://pdf.aydenjahola.com/api/v1/info/status"
    <<: *defaults_https

  - name: your-lastfm
    group: services
    url: "https://ylfm.local.aydenjahola.com"
    <<: *defaults_sso

  - name: reactive-resume
    group: services
    url: "https://resume.local.aydenjahola.com"
    <<: *defaults

  # --- Auth / Security ---
  - name: vaultwarden
    group: services
    url: "https://vault.aydenjahola.com"
    <<: *defaults_https

  - name: dependency-track
    group: security
    url: "https://dtrack.local.aydenjahola.com"
    <<: *defaults_https

  - name: trivy-server
    group: security
    url: "https://trivy.local.aydenjahola.com/healthz"
    <<: *defaults_https

  # --- Cloud / Apps ---
  - name: netronome
    group: services
    url: "https://netronome.aydenjahola.com"
    <<: *defaults

  - name: tracearr
    group: services
    url: "https://tracearr.local.aydenjahola.com"
    <<: *defaults_sso

  # --- Monitoring / Infra ---
  - name: gatus
    group: monitoring
    url: "https://gatus.aydenjahola.com"
    <<: *defaults_https

  - name: grafana
    group: monitoring
    url: "https://grafana.aydenjahola.com"
    <<: *defaults_https

  - name: grafana-alloy-odin
    group: monitoring
    url: "http://192.168.1.100:12345"
    <<: *defaults

  - name: grafana-alloy-thor
    group: monitoring
    url: "http://192.168.1.101:12345"
    <<: *defaults

  - name: grafana-alloy-loki
    group: monitoring
    url: "http://192.168.1.102:12345"
    <<: *defaults

  - name: loki
    group: monitoring
    url: "https://loki.local.aydenjahola.com/ready"
    <<: *defaults

  - name: uptime-kuma
    group: monitoring
    url: "https://status.aydenjahola.com/status/homelab"
    <<: *defaults_https

  - name: prometheus
    group: monitoring
    url: "https://prometheus.local.aydenjahola.com"
    <<: *defaults_sso

  - name: traefik
    group: infra
    url: "https://traefik.local.aydenjahola.com"
    <<: *defaults_https

  - name: dozzle-agent-odin
    group: infra
    # gRPC agent, no HTTP endpoint: check the port is accepting connections
    url: "tcp://192.168.1.100:7007"
    <<: *defaults
    conditions:
      - "[CONNECTED] == true"

  - name: dozzle-agent-thor
    group: infra
    # gRPC agent, no HTTP endpoint: check the port is accepting connections
    url: "tcp://192.168.1.101:7007"
    <<: *defaults
    conditions:
      - "[CONNECTED] == true"

  - name: dozzle-agent-loki
    group: infra
    # gRPC agent, no HTTP endpoint: check the port is accepting connections
    url: "tcp://192.168.1.102:7007"
    <<: *defaults
    conditions:
      - "[CONNECTED] == true"

  # --- Media Stack ---
  - name: bazarr
    group: media
    url: "https://bazarr.local.aydenjahola.com"
    <<: *defaults_sso

  - name: jellyfin
    group: media
    url: "https://jellyfin.local.aydenjahola.com"
    <<: *defaults_https

  - name: seerr
    group: media
    url: "https://seerr.local.aydenjahola.com"
    <<: *defaults_https

  - name: radarr
    group: media
    url: "https://radarr.local.aydenjahola.com"
    <<: *defaults_sso

  - name: sonarr
    group: media
    url: "https://sonarr.local.aydenjahola.com"
    <<: *defaults_sso

  - name: prowlarr
    group: media
    url: "https://prowl.local.aydenjahola.com"
    <<: *defaults_sso

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
EOH
      }

      resources {
        cpu        = 100
        memory     = 96
        memory_max = 512
      }
    }
  }

  group "db" {
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
      port "db" {
        to = 5432
      }
    }

    service {
      name = "gatus-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "300s"
          ignore_warnings = false
        }
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_DB       = {{ key "gatus/db/name" }}
POSTGRES_USER     = {{ key "gatus/db/user" }}
POSTGRES_PASSWORD = {{ key "gatus/db/password" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 512
      }
    }
  }
}
