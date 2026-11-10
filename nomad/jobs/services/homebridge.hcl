job "homebridge" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "loki"
  }

  group "homebridge" {
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

    task "homebridge" {
      driver = "docker"

      config {
        image        = "homebridge/homebridge:2026-11-02"
        network_mode = "host"
        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/homebridge:rw",
        ]
      }

      env {
        TZ           = "Europe/Dublin"
        ENABLE_AVAHI = "1"
      }

      resources {
        cpu        = 100
        memory     = 352
        memory_max = 512
      }
    }
  }
}
