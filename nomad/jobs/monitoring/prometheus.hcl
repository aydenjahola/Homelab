job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prometheus.local.aydenjahola.com"
  }

  group "prometheus" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
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
      port "web" {
        to = 9090
      }
    }

    service {
      name = "prometheus"
      port = "web"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.prometheus.entrypoints=https",
        "traefik.http.routers.prometheus.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.prometheus.middlewares=authentik@consulcatalog",
      ]
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:v3.16.0"
        ports = ["web"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/prometheus",
          "local/prometheus.yml:/prometheus/prometheus.yml",
        ]

        args = [
          "--config.file=/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus"
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination = "local/prometheus.yml"
        data        = <<EOH
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: "node-exporters"
    static_configs:
      - targets:
        - "192.168.1.100:9100"
        - "192.168.1.101:9100"
        - "192.168.1.102:9100"

  - job_name: "nomad_metrics"
    metrics_path: "/v1/metrics"
    params:
      format: ["prometheus"]
    static_configs:
      - targets:
        - "192.168.1.100:4646"
        - "192.168.1.101:4646"
        - "192.168.1.102:4646"

  - job_name: "loki"
    scheme: https
    metrics_path: /metrics
    static_configs:
      - targets:
        - "loki.local.aydenjahola.com"

  - job_name: "grafana-alloy"
    static_configs:
      - targets:
        - "192.168.1.100:12345"
        - "192.168.1.101:12345"
        - "192.168.1.102:12345"

  - job_name: "authentik"
    consul_sd_configs:
      - server: "{{ env "attr.unique.network.ip-address" }}:8500"
        services: ["authentik-metrics"]
EOH
      }

      resources {
        cpu        = 200
        memory     = 288
        memory_max = 512
      }
    }
  }
}
