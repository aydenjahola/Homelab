job "inaamessawi-wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain  = "inaamessawi.com"
    domain2 = "www.inaamessawi.com"
  }

  group "inaamessawi" {
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
      name = "inaamessawi-wordpress"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.inaamessawi.rule=Host(`${NOMAD_META_domain}`) || Host(`${NOMAD_META_domain2}`)",
        "traefik.http.routers.inaamessawi.entrypoints=https",
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
WORDPRESS_DB_USER={{ key "inaamessawi/db/user" }}
WORDPRESS_DB_PASSWORD={{ key "inaamessawi/db/password" }}
WORDPRESS_DB_NAME={{ key "inaamessawi/db/name" }}
EOH
      }
    }

    service {
      name = "inaamessawi-db"
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
MYSQL_ROOT_PASSWORD={{ key "inaamessawi/db/root/password" }}
MYSQL_DATABASE={{ key "inaamessawi/db/name" }}
MYSQL_USER={{ key "inaamessawi/db/user" }}
MYSQL_PASSWORD={{ key "inaamessawi/db/password" }}
EOH
      }
    }
  }
}


