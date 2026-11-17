job "adguard" {
  datacenters = ["dc1"]
  type        = "system"

  meta {
    domain = "adguard.local.aydenjahola.com"
  }

  group "adguard" {
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

    # Query log, stats and filter cache stay on local disk so DNS keeps working when the NAS is down.
    ephemeral_disk {
      size   = 1024
      sticky = true
    }

    network {
      port "dns" {
        static = 53
        to     = 53
      }

      port "http" {
        to = 3000
      }

      port "metrics" {
        to = 9618
      }
    }

    service {
      name = "adguard-dns"
      port = "dns"
      task = "adguard"

      check {
        name     = "adguard-dns-resolve"
        type     = "script"
        command  = "nslookup"
        args     = ["nas.local.aydenjahola.com", "127.0.0.1"]
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "2m"
        }
      }
    }

    service {
      name = "adguard"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.adguard.entrypoints=https",
        "traefik.http.routers.adguard.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.adguard.middlewares=lan-only@file",
        "traefik.http.services.adguard.loadbalancer.sticky.cookie=true",
        "traefik.http.services.adguard.loadbalancer.sticky.cookie.name=adguard_node",
        "traefik.http.services.adguard.loadbalancer.sticky.cookie.secure=true",
        "traefik.http.services.adguard.loadbalancer.sticky.cookie.httponly=true",
      ]

      check {
        name     = "adguard-http"
        type     = "http"
        path     = "/login.html"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "2m"
        }
      }
    }

    service {
      name = "adguard-exporter"
      port = "metrics"

      check {
        name     = "adguard-exporter-health"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "2m"
        }
      }
    }

    task "adguard" {
      driver = "docker"

      # The rendered config is copied over AdGuard's on every start: the repo is the source of truth.
      config {
        image      = "adguard/adguardhome:v0.107.80"
        ports      = ["dns", "http"]
        entrypoint = ["/bin/sh", "-c"]

        args = [
          "mkdir -p /alloc/data/conf /alloc/data/work && cp /local/AdGuardHome.yaml /alloc/data/conf/AdGuardHome.yaml && exec /opt/adguardhome/AdGuardHome --no-check-update -c /alloc/data/conf/AdGuardHome.yaml -w /alloc/data/work",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/AdGuardHome.yaml"
        error_on_missing_key = true
        data                 = <<EOH
http:
  address: 0.0.0.0:3000
  session_ttl: 720h
users: []
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  ratelimit: 0
  refuse_any: true
  upstream_dns:
    - https://dns.quad9.net/dns-query
    - https://cloudflare-dns.com/dns-query
    - tls://dns.quad9.net
    - tls://one.one.one.one
    - "[/station/]192.168.1.1"
  bootstrap_dns:
    - 9.9.9.9
    - 149.112.112.112
    - 1.1.1.1
    - 1.0.0.1
  fallback_dns:
    - 9.9.9.9
    - 1.1.1.1
  upstream_mode: load_balance
  allowed_clients:
    - 127.0.0.0/8
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - ::1/128
    - fc00::/7
    - fe80::/10
  cache_enabled: true
  cache_size: 4194304
  cache_optimistic: true
  enable_dnssec: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams:
    - 192.168.1.1
  serve_plain_dns: true
  hostsfile_enabled: false
querylog:
  interval: 168h
  size_memory: 1000
  enabled: true
  file_enabled: true
statistics:
  interval: 168h
  enabled: true
# Blocklists. One HaGeZi Multi tier only (Pro); TIF full is the threat add-on.
# Fake, TIF mini/medium, Multi Normal and OISD Small are subsets of what's here, so they're left out.
# The uBlock Origin lists are browser lists: AdGuard Home applies only their hostname rules
# and ignores cosmetic, path and browser-only rules. The AdGuard-converted uBO badware list (id 50) carries the rest of badware.txt.
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_48.txt
    name: HaGeZi's Pro Blocklist
    id: 48
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_27.txt
    name: OISD Blocklist Big
    id: 27
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_44.txt
    name: HaGeZi's Threat Intelligence Feeds
    id: 44
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_54.txt
    name: HaGeZi's DynDNS Blocklist
    id: 54
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_55.txt
    name: HaGeZi's Badware Hoster Blocklist
    id: 55
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_67.txt
    name: HaGeZi's Apple Tracker Blocklist
    id: 67
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt
    name: Malicious URL Blocklist (URLHaus)
    id: 11
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt
    name: Dandelion Sprout's Anti-Malware List
    id: 12
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_50.txt
    name: uBlock filters - Badware risks (AdGuard DNS version)
    id: 50
  - enabled: true
    url: https://ublockorigin.github.io/uAssets/filters/filters.txt
    name: uBlock filters
    id: 101
  - enabled: true
    url: https://ublockorigin.github.io/uAssets/filters/badware.txt
    name: uBlock filters - Badware risks
    id: 102
  - enabled: true
    url: https://ublockorigin.github.io/uAssets/filters/privacy.txt
    name: uBlock filters - Privacy
    id: 103
  - enabled: true
    url: https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt
    name: uBlock filters - Quick fixes
    id: 104
  - enabled: true
    url: https://ublockorigin.github.io/uAssets/filters/unbreak.txt
    name: uBlock filters - Unbreak
    id: 105
  - enabled: true
    url: https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext
    name: Peter Lowe's Ad and tracking server list (uBlock Origin source)
    id: 106
whitelist_filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_45.txt
    name: HaGeZi's Allowlist Referral
    id: 45
# Windows uses this host for Known Game List updates (CPU core parking on dual-CCD Ryzen). OISD blocks it.
# Listed in HaGeZi's Microsoft known-issues (share/microsoft.txt).
user_rules:
  - "@@||settings-sandbox.data.microsoft.com^"
dhcp:
  enabled: false
filtering:
  blocking_mode: default
  rewrites:
    - domain: "*.local.aydenjahola.com"
      answer: 192.168.1.240
      enabled: true
    - domain: nas.local.aydenjahola.com
      answer: 192.168.1.103
      enabled: true
    # Split horizon: public hostnames resolve to Traefik on the LAN instead of hairpinning
    # through Cloudflare (in-cluster monitors got CrowdSec-banned under the dynamic home IP).
    # The apex isn't matched by the wildcard. blog isn't on Traefik: answer "A"/"AAAA" keeps the upstream records.
    - domain: "*.aydenjahola.com"
      answer: 192.168.1.240
      enabled: true
    - domain: blog.aydenjahola.com
      answer: A
      enabled: true
    - domain: blog.aydenjahola.com
      answer: AAAA
      enabled: true
    - domain: www.aydenjahola.com
      answer: A
      enabled: true
    - domain: www.aydenjahola.com
      answer: AAAA
      enabled: true
    - domain: spotify-stats.aydenjahola.com
      answer: A
      enabled: true
    - domain: spotify-stats.aydenjahola.com
      answer: AAAA
      enabled: true
    - domain: re.aydenjahola.com
      answer: A
      enabled: true
    - domain: re.aydenjahola.com
      answer: AAAA
      enabled: true
  filters_update_interval: 24
  filtering_enabled: true
  rewrites_enabled: true
  parental_enabled: false
  safebrowsing_enabled: true
  protection_enabled: true
log:
  enabled: true
  verbose: false
schema_version: 34
EOH
      }

      resources {
        cpu = 200
        # ~2.2M filter rules hold ~290 MiB RSS. The 24h filter reload briefly keeps old and new rule sets in memory.
        memory     = 384
        memory_max = 1024
      }
    }

    task "adguard-exporter" {
      driver = "docker"

      config {
        image = "ghcr.io/henrywhitaker3/adguard-exporter:v1.2.3"
        ports = ["metrics"]
      }

      env {
        TZ              = "Europe/Dublin"
        INTERVAL        = "30s"
        ADGUARD_SERVERS = "http://${NOMAD_ADDR_http}"
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 128
      }
    }
  }
}
