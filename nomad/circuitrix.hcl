job "circuitrix" {
  datacenters = ["dc1"]
  type = "service"

  group "circuitrix" {
    count = 1

    task "circuitrix" {
      driver = "docker"

      config {
        image = "ghcr.io/aydenjahola/circuitrix:music"
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

MONGODB_URI={{ key "gomlbot/mongo/db" }}

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
  }
}
