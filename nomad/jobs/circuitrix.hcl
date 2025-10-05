job "circuitrix" {
  datacenters = ["dc1"]
  type = "service"

  group "circuitrix" {
    count = 1

    network {
      port "db" {
        to = 27017
      }
    }

    task "circuitrix" {
      driver = "docker"

      config {
        image = "ghcr.io/aydenjahola/circuitrix:main"
      }

      resources {
        cpu = 500
        memory = 256
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
BOT_TOKEN={{ key "gomlbot/discord/token" }}

MONGODB_URI=mongodb://{{ key "gomlbot/mongodb/username" }}:{{ key "gomlbot/mongodb/password" }}@{{ env "NOMAD_ADDR_db" }}/?retryWrites=true&w=majority&appName={{ key "gomlbot/mongodb/name" }}

GENIUS_API_TOKEN={{ key "gomlbot/genius/key" }}

# Nodemailer
EMAIL_NAME={{ key "gomlbot/email/name" }}
EMAIL_USER={{ key "gomlbot/email/user" }}
EMAIL_PASS={{ key "gomlbot/email/pass" }}

# API
RAPIDAPI_KEY={{ key "gomlbot/rapid/api/key" }}
WORDNIK_API_KEY={{ key "gomlbot/wordnik/api/key" }}

TRACKER_API_URL={{ key "gomlbot/tracker/api/url" }}
TRACKER_API_KEY={{ key "gomlbot/tracker/api/key" }}

HUGGING_FACE_API_KEY={{ key "gomlbot/huggingface/api/key" }}

# Database
MONGODB_URI={{ key "gomlbot/mongo/db/url" }}

GENIUS_API_TOKEN={{ key "gomlbot/genius/key" }}
EOH
      }
    }

    task "mongodb" {
      driver = "docker"

      config {
        image = "mongo:latest"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/data/db"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
MONGO_INITDB_ROOT_USERNAME="{{ key "circuitrix/mongodb/username" }}"
MONGO_INITDB_ROOT_PASSWORD="{{ key "circuitrix/mongodb/password" }}"
EOH
      }

      resources {
        cpu = 300
        memory = 512
      }
    }
  }
}
