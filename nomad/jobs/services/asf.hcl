job "archisteamfarm" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "asf.local.aydenjahola.com"
  }

  group "asf" {
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
      port "http" {
        to = 1242
      }
    }

    service {
      name = "archisteamfarm"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.asf.entrypoints=https",
        "traefik.http.routers.asf.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.asf.middlewares=authentik@consulcatalog",
      ]
    }

    task "asf" {
      driver = "docker"

      config {
        image = "justarchi/archisteamfarm:7.0.0.8"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/config:/app/config",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/logs:/app/logs",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/plugins:/app/plugins",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      resources {
        cpu        = 100
        memory     = 160
        memory_max = 512
      }
    }
  }
}
