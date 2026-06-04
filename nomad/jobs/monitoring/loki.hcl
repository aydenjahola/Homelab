job "loki" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "loki.local.aydenjahola.com"
  }

  group "loki" {
    count = 1

    network {
      port "http" {
        to = 3100
      }

      port "grpc" {
        to = 9096
      }
    }

    service {
      name = "loki"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.loki.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.loki.entrypoints=https"
      ]

      check {
        name     = "loki-ready"
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "loki" {
      driver = "docker"

      config {
        image = "grafana/loki:latest"
        ports = ["http", "grpc"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/loki",
          "local/loki.yml:/etc/loki/loki.yml"
        ]

        args = [
          "-config.file=/etc/loki/loki.yml"
        ]
      }

      template {
        destination = "local/loki.yml"
        data        = <<EOH
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h
  allow_structured_metadata: true

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  delete_request_store: filesystem

ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
EOH
      }

      resources {
        cpu    = 500
        memory = 800
      }
    }
  }
}
