job "grafana-alloy" {
  datacenters = ["dc1"]
  type        = "system"

  group "grafana-alloy" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "http" {
        static = 12345
      }
    }

    service {
      name = "grafana-alloy"
      port = "http"

      check {
        name     = "grafana-alloy-http"
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "grafana-alloy" {
      driver = "docker"

      config {
        image = "grafana/alloy:v1.21.3"
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
          "/opt/nomad:/host/nomad:ro",
        ]
      }

      env {
        TZ = "Europe/Dublin"
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

  // service_name drives Grafana Logs Drilldown: one "host-<node>" entry per server.
  labels = {
    source       = "journal",
    node         = "{{ env "node.unique.name" }}",
    service_name = "host-{{ env "node.unique.name" }}",
  }
}

loki.source.file "host_logs" {
  targets = [
    {
      __path__     = "/host/var/log/**/*.log",
      source       = "file",
      job          = "host-logs",
      node         = "{{ env "node.unique.name" }}",
      service_name = "host-{{ env "node.unique.name" }}",
    },
    {
      __path__     = "/host/var/log/syslog",
      source       = "file",
      job          = "syslog",
      node         = "{{ env "node.unique.name" }}",
      service_name = "host-{{ env "node.unique.name" }}",
    },
    {
      __path__     = "/host/var/log/auth.log",
      source       = "file",
      job          = "auth",
      node         = "{{ env "node.unique.name" }}",
      service_name = "host-{{ env "node.unique.name" }}",
    },
  ]

  forward_to = [loki.write.loki.receiver]

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}

// Nomad task logs. The task name comes from the file name
// (<alloc>/alloc/logs/<task>.<stream>.<n>) so logs can be filtered per task.
local.file_match "nomad_alloc_logs" {
  path_targets = [{
    __path__ = "/host/nomad/alloc/*/alloc/logs/*.std*.*",
    source   = "nomad",
    node     = "{{ env "node.unique.name" }}",
  }]
  sync_period = "10s"
}

discovery.relabel "nomad_alloc_logs" {
  targets = local.file_match.nomad_alloc_logs.targets

  rule {
    source_labels = ["__path__"]
    regex         = "/host/nomad/alloc/[^/]+/alloc/logs/(.+)[.](stdout|stderr)[.][0-9]+"
    target_label  = "task"
    replacement   = "$1"
  }

  rule {
    source_labels = ["__path__"]
    regex         = "/host/nomad/alloc/[^/]+/alloc/logs/(.+)[.](stdout|stderr)[.][0-9]+"
    target_label  = "stream"
    replacement   = "$2"
  }

  // Drilldown lists each Nomad task as its own service.
  rule {
    source_labels = ["__path__"]
    regex         = "/host/nomad/alloc/[^/]+/alloc/logs/(.+)[.](stdout|stderr)[.][0-9]+"
    target_label  = "service_name"
    replacement   = "$1"
  }
}

loki.source.file "nomad_alloc_logs" {
  targets    = discovery.relabel.nomad_alloc_logs.output
  forward_to = [loki.write.loki.receiver]
}
EOH
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 500
      }
    }
  }
}
