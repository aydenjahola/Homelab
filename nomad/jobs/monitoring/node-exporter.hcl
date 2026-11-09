job "node-exporter" {
  datacenters = ["dc1"]
  type        = "system"

  group "node-exporter" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    task "node-exporter" {
      driver = "docker"

      config {
        image = "prom/node-exporter:v1.12.1"

        network_mode = "host"
        pid_mode     = "host"

        volumes = ["/:/host:ro,rslave"]
        args = [
          "--path.rootfs=/host"
        ]
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }
    }
  }
}
