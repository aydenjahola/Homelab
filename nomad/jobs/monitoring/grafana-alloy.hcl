job "grafana-alloy" {
  datacenters = ["dc1"]
  type        = "system"

  group "grafana-alloy" {
    network {
      port "http" {
        static = 12345
      }
    }

    service {
      name = "grafana-alloy"
      port = "http"

      check {
        name     = "alloy-health"
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "grafana-alloy" {
      driver = "docker"

      config {
        image = "grafana/alloy:latest"
        ports = ["http"]

        args = [
          "run",
          "--server.http.listen-addr=0.0.0.0:12345",
          "--storage.path=/var/lib/alloy/data",
          "/etc/alloy/config.alloy"
        ]

        volumes = [
          "local/config.alloy:/etc/alloy/config.alloy",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/alloy",

          # Host logs
          "/var/log:/host/var/log:ro",

          # Journald logs
          "/var/log/journal:/var/log/journal:ro",
          "/run/log/journal:/run/log/journal:ro",
          "/etc/machine-id:/etc/machine-id:ro",

          # Nomad allocation logs.
          "/opt/nomad:/host/nomad:ro"
        ]
      }

      template {
        destination = "local/config.alloy"
        data        = <<EOH
logging {
  level  = "info"
  format = "logfmt"
}

loki.write "loki" {
  endpoint {
    url = "https://loki.local.aydenjahola.com/loki/api/v1/push"
  }
}

loki.relabel "journal" {
  forward_to = []

  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }

  rule {
    source_labels = ["__journal__hostname"]
    target_label  = "host"
  }

  rule {
    source_labels = ["__journal_priority_keyword"]
    target_label  = "level"
  }
}

loki.source.journal "systemd" {
  forward_to    = [loki.write.loki.receiver]
  relabel_rules = loki.relabel.journal.rules

  labels = {
    source = "journal",
    node   = "{{ env "node.unique.name" }}",
  }
}

loki.source.file "host_logs" {
  targets = [
    {
      __path__ = "/host/var/log/**/*.log",
      source   = "file",
      job      = "host-logs",
      node     = "{{ env "node.unique.name" }}",
    },
    {
      __path__ = "/host/var/log/syslog",
      source   = "file",
      job      = "syslog",
      node     = "{{ env "node.unique.name" }}",
    },
    {
      __path__ = "/host/var/log/auth.log",
      source   = "file",
      job      = "auth",
      node     = "{{ env "node.unique.name" }}",
    },
  ]

  forward_to = [loki.write.loki.receiver]

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}

loki.source.file "nomad_alloc_logs" {
  targets = [
    {
      __path__ = "/host/nomad/alloc/*/alloc/logs/*.stdout.*",
      source   = "nomad",
      stream   = "stdout",
      node     = "{{ env "node.unique.name" }}",
    },
    {
      __path__ = "/host/nomad/alloc/*/alloc/logs/*.stderr.*",
      source   = "nomad",
      stream   = "stderr",
      node     = "{{ env "node.unique.name" }}",
    },
  ]

  forward_to = [loki.write.loki.receiver]

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}
EOH
      }

      resources {
        cpu    = 200
        memory = 500
      }
    }
  }
}
