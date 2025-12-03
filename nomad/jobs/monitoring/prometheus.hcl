job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prometheus.local.aydenjahola.com"
  }

  group "prometheus" {
    count = 1

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
        "traefik.http.routers.prometheus.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.prometheus.entrypoints=https"
      ]
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:latest"
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
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
