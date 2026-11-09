job "node-exporter" {
  datacenters = ["dc1"]
  type        = "system"

  group "node-exporter" {
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
