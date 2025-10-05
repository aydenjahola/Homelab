job "janan-wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "janan.aydenjahola.com"
  }

  group "janan" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "db" {
        to = 3306
      }
    }

    service {
      name = "janan-wordpress"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.janan.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.janan.entrypoints=https",
      ]
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = "wordpress:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/wp_data:/var/www/html:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
WORDPRESS_DB_HOST={{ env "NOMAD_ADDR_db" }}
WORDPRESS_DB_USER={{ key "janan/db/user" }}
WORDPRESS_DB_PASSWORD={{ key "janan/db/password" }}
WORDPRESS_DB_NAME={{ key "janan/db/name" }}
EOH
      }
    }

    service {
      name = "janan-db"
      port = "db"
    }

    task "mariadb" {
      driver = "docker"

      config {
        image   = "mariadb:10.6.4-focal"
        ports   = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/db_data:/var/lib/mysql:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      template {
        destination = "local/.env"
        env         = true
        data = <<EOH
MYSQL_ROOT_PASSWORD={{ key "janan/db/root/password" }}
MYSQL_DATABASE={{ key "janan/db/name" }}
MYSQL_USER={{ key "janan/db/user" }}
MYSQL_PASSWORD={{ key "janan/db/password" }}
EOH
      }
    }
  }
}
