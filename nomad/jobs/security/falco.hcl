job "falco" {
  datacenters = ["dc1"]
  type        = "system"

  group "falco" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "metrics" {
        static = 8765
      }
    }

    service {
      name = "falco"
      port = "metrics"

      check {
        name     = "falco-health"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "falco" {
      driver = "docker"

      config {
        image        = "falcosecurity/falco:0.45.2"
        command      = "/usr/bin/falco"
        privileged   = true
        pid_mode     = "host"
        network_mode = "host"

        args = [
          "-o", "engine.kind=modern_ebpf",
          "-o", "json_output=true",
          "-o", "json_include_output_property=true",
          "-o", "json_include_tags_property=true",
          "-o", "stdout_output.enabled=true",
          "-o", "priority=notice",
          "-o", "webserver.enabled=true",
          "-o", "webserver.listen_port=8765",
          "-o", "webserver.prometheus_metrics_enabled=true",
          "-o", "metrics.enabled=true",
          "-o", "metrics.interval=1m",
          "-o", "metrics.output_rule=false",
        ]

        volumes = [
          "/var/run/docker.sock:/host/var/run/docker.sock:ro",
          "/proc:/host/proc:ro",
          "/etc:/host/etc:ro",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      resources {
        cpu        = 200
        memory     = 256
        memory_max = 512
      }
    }
  }
}
