job "authentik" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "auth.aydenjahola.com"
  }

  group "authentik" {
    count = 1

    update {
      healthy_deadline  = "10m"
      progress_deadline = "15m"
    }

    network {
      port "http" {
        to = 9000
      }

      port "metrics" {
        to = 9300
      }
    }

    service {
      name = "authentik"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.authentik.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.authentik.entrypoints=https",
      ]

      check {
        name     = "authentik-live"
        type     = "http"
        path     = "/-/health/live/"
        interval = "10s"
        timeout  = "3s"
      }
    }

    service {
      name = "authentik-metrics"
      port = "metrics"
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for authentik db; sleep 2; done"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DB_USER={{ key "authentik/db/user" }}
DB_NAME={{ key "authentik/db/name" }}

{{ range service "authentik-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2026.8.5"
        ports = ["http", "metrics"]
        args  = ["server"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data:rw",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
AUTHENTIK_SECRET_KEY={{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED=false

AUTHENTIK_POSTGRESQL__NAME={{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER={{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD={{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }

    task "worker" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2026.8.5"
        args  = ["worker"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/data:rw",
          "local/blueprints:/blueprints/custom:ro",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
AUTHENTIK_SECRET_KEY={{ key "authentik/secret/key" }}
AUTHENTIK_ERROR_REPORTING__ENABLED=false

AUTHENTIK_BOOTSTRAP_PASSWORD={{ key "authentik/bootstrap/password" }}
AUTHENTIK_BOOTSTRAP_EMAIL={{ key "authentik/bootstrap/email" }}

AUTHENTIK_POSTGRESQL__NAME={{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__USER={{ key "authentik/db/user" }}
AUTHENTIK_POSTGRESQL__PASSWORD={{ key "authentik/db/password" }}
{{ range service "authentik-db" }}
AUTHENTIK_POSTGRESQL__HOST={{ .Address }}
AUTHENTIK_POSTGRESQL__PORT={{ .Port }}
{{ end }}
EOH
      }

      template {
        destination = "local/blueprints/homelab-base.yaml"
        change_mode = "noop"
        data        = <<EOH
version: 1
metadata:
  name: homelab-base
entries:
  - model: authentik_core.group
    id: homelab-admins
    identifiers:
      name: homelab-admins
    attrs:
      is_superuser: true

  - model: authentik_core.user
    identifiers:
      username: {{ key "authentik/user/username" }}
    attrs:
      name: {{ key "authentik/user/name" }}
      email: {{ key "authentik/user/email" }}
      is_active: true
      groups:
        - !KeyOf homelab-admins
        - !Find [authentik_core.group, [name, authentik Admins]]

  - model: authentik_stages_authenticator_validate.authenticatorvalidatestage
    identifiers:
      name: default-authentication-mfa-validation
    attrs:
      not_configured_action: configure
      device_classes:
        - totp
        - webauthn
      configuration_stages:
        - !Find [authentik_stages_authenticator_totp.authenticatortotpstage, [name, default-authenticator-totp-setup]]
        - !Find [authentik_stages_authenticator_webauthn.authenticatorwebauthnstage, [name, default-authenticator-webauthn-setup]]

  - model: authentik_core.user
    identifiers:
      username: akadmin
    attrs:
      is_active: false
EOH
      }

      template {
        destination = "local/blueprints/app-grafana.yaml"
        change_mode = "noop"
        data        = <<EOH
version: 1
metadata:
  name: app-grafana
entries:
  - model: authentik_providers_oauth2.oauth2provider
    id: grafana-provider
    identifiers:
      name: grafana
    attrs:
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
      client_type: confidential
      client_id: {{ key "authentik/oidc/grafana/client_id" }}
      client_secret: {{ key "authentik/oidc/grafana/client_secret" }}
      redirect_uris:
        - matching_mode: strict
          url: https://grafana.aydenjahola.com/login/generic_oauth
      signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-openid]]
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-email]]
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-profile]]
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-offline_access]]

  - model: authentik_core.application
    id: grafana-app
    identifiers:
      slug: grafana
    attrs:
      name: Grafana
      provider: !KeyOf grafana-provider
      meta_launch_url: https://grafana.aydenjahola.com
      meta_icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/grafana.svg
      open_in_new_tab: true
      policy_engine_mode: any

  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf grafana-app
      group: !Find [authentik_core.group, [name, homelab-admins]]
    attrs:
      order: 0
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 5432
      }
    }

    service {
      name = "authentik-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
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
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "authentik/db/name" }}
POSTGRES_USER     = {{ key "authentik/db/user" }}
POSTGRES_PASSWORD = {{ key "authentik/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
