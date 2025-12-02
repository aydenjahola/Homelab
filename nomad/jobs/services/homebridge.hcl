job "homebridge" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "loki"
  }

  group "homebridge" {
    count = 1

    task "homebridge" {
      driver = "docker"

      config {
        image        = "homebridge/homebridge:latest"
        network_mode = "host"
        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/homebridge:rw",
        ]
      }

      env {
        TZ = "Europe/Dublin"
        ENABLE_AVAHI = "1"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
