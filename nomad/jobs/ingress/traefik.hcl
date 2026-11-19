job "traefik" {
  datacenters = ["dc1"]
  type        = "system"

  meta {
    domain = "traefik.local.aydenjahola.com"
  }

  group "traefik" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "http" {
        static = 80
      }

      port "https" {
        static = 443
      }

      port "admin" {
        to = 8080
      }
    }

    service {
      name = "traefik"
      port = "admin"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.api.entrypoints=https",
        "traefik.http.routers.api.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.api.middlewares=lan-only@file",
        "traefik.http.routers.api.service=api@internal",
      ]
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v3.7.17"
        network_mode = "host"

        volumes = [
          "/etc/localtime:/etc/localtime:ro",
          "local/traefik.yml:/traefik.yml:ro",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/${node.unique.name}/acme.json:/acme.json",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/${node.unique.name}/traefik_logs:/traefik_logs",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/plugins-local:/plugins-local:ro",
          "local/dynamic:/dynamic:ro",
        ]
      }


      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
CF_API_EMAIL = {{ key "traefik/cf/email" }}
CF_API_KEY   = {{ key "traefik/cf/api" }}
EOH
      }

      template {
        destination = "local/dynamic/lan-only.yml"
        change_mode = "noop"
        data        = <<EOH
http:
  middlewares:
    lan-only:
      ipAllowList:
        sourceRange:
          - "192.168.1.0/24"
          - "172.16.0.0/12"
          - "10.0.0.0/8"
          - "127.0.0.1/32"
EOH
      }

      template {
        destination          = "local/dynamic/crowdsec.yml"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
http:
  middlewares:
    crowdsec:
      plugin:
        bouncer:
          enabled: true
          crowdsecMode: stream
          updateIntervalSeconds: 60
          updateMaxFailure: -1
          crowdsecLapiScheme: http
          # Local loopback entrypoint that Traefik routes to wherever crowdsec runs.
          # The plugin's stream ticker keeps the host it started with, so the
          # host must never change (a Consul address went stale on every move).
          crowdsecLapiHost: "127.0.0.1:8081"
          crowdsecLapiKey: "{{ key "crowdsec/bouncer/traefik" }}"
          forwardedHeadersTrustedIPs:
            - "173.245.48.0/20"
            - "103.21.244.0/22"
            - "103.22.200.0/22"
            - "103.31.4.0/22"
            - "141.101.64.0/18"
            - "108.162.192.0/18"
            - "190.93.240.0/20"
            - "188.114.96.0/20"
            - "197.234.240.0/22"
            - "198.41.128.0/17"
            - "162.158.0.0/15"
            - "104.16.0.0/13"
            - "104.24.0.0/14"
            - "172.64.0.0/13"
            - "131.0.72.0/22"
            - "2400:cb00::/32"
            - "2606:4700::/32"
            - "2803:f800::/32"
            - "2405:b500::/32"
            - "2405:8100::/32"
            - "2a06:98c0::/29"
            - "2c0f:f248::/32"
          clientTrustedIPs:
            - "192.168.1.0/24"
            - "172.16.0.0/12"
            - "127.0.0.1/32"
EOH
      }

      template {
        destination = "local/traefik.yml"
        data        = <<EOH
api:
  dashboard: true

ping: {}

entryPoints:
  # Loopback only: the crowdsec bouncer plugin reaches the LAPI through here.
  crowdsec-lapi:
    address: "127.0.0.1:8081"

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
    forwardedHeaders:
      trustedIPs:
        - "173.245.48.0/20"
        - "103.21.244.0/22"
        - "103.22.200.0/22"
        - "103.31.4.0/22"
        - "141.101.64.0/18"
        - "108.162.192.0/18"
        - "190.93.240.0/20"
        - "188.114.96.0/20"
        - "197.234.240.0/22"
        - "198.41.128.0/17"
        - "162.158.0.0/15"
        - "104.16.0.0/13"
        - "104.24.0.0/14"
        - "172.64.0.0/13"
        - "131.0.72.0/22"
        - "2400:cb00::/32"
        - "2606:4700::/32"
        - "2803:f800::/32"
        - "2405:b500::/32"
        - "2405:8100::/32"
        - "2a06:98c0::/29"
        - "2c0f:f248::/32"
    http:
      middlewares:
        - crowdsec@file
      tls:
        certresolver: cloudflare
        domains:
          - main: "aydenjahola.com"
            sans: "*.aydenjahola.com"
          - main: "local.aydenjahola.com"
            sans: "*.local.aydenjahola.com"

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

accessLog:
  format: json
  fields:
    defaultMode: keep
    headers:
      defaultMode: drop
      names:
        User-Agent: keep

experimental:
  localPlugins:
    bouncer:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin

providers:
  file:
    directory: /dynamic
    watch: true
  consulCatalog:
    endpoint:
      address: "127.0.0.1:8500"
      scheme: "http"
    exposedByDefault: false

metrics:
  addInternals: true
  prometheus:
    entryPoint: traefik
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true
EOH
      }

      resources {
        cpu        = 200
        memory     = 96
        memory_max = 512
      }
    }
  }
}
