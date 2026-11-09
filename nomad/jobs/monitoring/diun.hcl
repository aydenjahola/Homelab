job "diun" {
  datacenters = ["dc1"]
  type        = "service"

  group "diun" {
    count = 1

    task "diun" {
      driver = "docker"

      config {
        image = "crazymax/diun:4.33.1"
        args  = ["serve", "--config", "local/diun.yml"]

        auth {
          username = "${DOCKER_USER}"
          password = "${DOCKER_PASS}"
        }

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data:rw",
          "/etc/timezone:/etc/timezone:ro",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env = {
        "NOMAD_ADDR"           = "http://${attr.unique.network.ip-address}:4646/",
        "DIUN_PROVIDERS_NOMAD" = "true"
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
DOCKER_USER={{ key "docker/hub/user" }}
DOCKER_PASS={{ key "docker/hub/token" }}
EOH
      }

      template {
        destination = "local/diun.yml"
        data        = <<EOH
db:
  path: /data/diun.db

watch:
  workers: 2
  schedule: "0 3 * * *"
  jitter: 2m
  firstCheckNotif: false
  runOnStartup: true

providers:
  nomad:
    watchByDefault: true

regopts:
  - name: ghcr.io
    selector: image
    username: "{{ key "docker/ghcr/user" }}"
    password: "{{ key "docker/ghcr/token" }}"
  - name: "docker.io"
    selector: image
    username: "{{ key "docker/hub/user" }}"
    password: "{{ key "docker/hub/token" }}"
  - name: "registry-1.docker.io"
    selector: image
    username: "{{ key "docker/hub/user" }}"
    password: "{{ key "docker/hub/token" }}"

notif:
  discord:
    webhookURL: "{{ key "diun/discord/webhook" }}"
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }
    }
  }
}
