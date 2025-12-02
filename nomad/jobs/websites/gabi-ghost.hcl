job "ghost" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain       = "gabi.aydenjahola.com"
  }

  group "ghost" {
    count = 1

    network {
      port "http" {
        to = 2368
      }
      port "db" {
        to = 3306
      }
    }

    service {
      name = "ghost"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ghost.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.ghost.entrypoints=https",
      ]
    }

    task "ghost" {
      driver = "docker"

      config {
        image = "ghost:6-alpine"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/ghost/content",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NODE_ENV=production

# Site URLs
url=https://{{ env "NOMAD_META_domain" }}

# Database 
database__client=mysql
database__connection__host={{ env "NOMAD_HOST_IP_db" }}
database__connection__port={{ env "NOMAD_HOST_PORT_db" }}
database__connection__user={{ key "ghost/mysql/user" }}
database__connection__password={{ key "ghost/mysql/password" }}
database__connection__database={{ key "ghost/mysql/name" }}

security__staffDeviceVerification="false"
mail__from={{ key "ghost/smtp/from" }}
mail__transport="SMTP"
mail__options__host="smtp.resend.com"
mail__options__port="587"
mail__options__secure="true"
mail__options__auth__user="{{ key "ghost/smtp/user" }}"
mail__options__auth__pass="{{ key "ghost/smtp/password" }}"
EOH
      }

      resources {
        cpu    = 500
        memory = 768
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "mysql:8.0"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/mysql",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
MYSQL_ROOT_PASSWORD={{ key "ghost/mysql/root/password" }}
MYSQL_USER={{ key "ghost/mysql/user" }}
MYSQL_PASSWORD={{ key "ghost/mysql/password" }}
MYSQL_DATABASE={{ key "ghost/mysql/name" }}
EOH
      }

      resources {
        cpu    = 400
        memory = 1024
      }
    }
  }
}
