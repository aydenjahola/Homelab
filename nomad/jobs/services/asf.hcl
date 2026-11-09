job "archisteamfarm" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "asf.local.aydenjahola.com"
  }

  group "asf" {
    count = 1

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
        image = "justarchi/archisteamfarm:6.3.11.7"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/config:/app/config",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/logs:/app/logs",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/plugins:/app/plugins",
        ]
      }

      resources {
        cpu        = 500
        memory     = 160
        memory_max = 512
      }
    }
  }
}
