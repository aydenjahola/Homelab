job "eqpaint-wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "eqpaint.aydenjahola.com"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 3306
      }
    }

    service {
      name = "eqpaint-db"
      port = "db"

      check {
        name     = "mariadb-tcp"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "mariadb" {
      driver = "docker"

      config {
        image = "mariadb:10.6"
        ports = ["db"]

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
        change_mode = "restart"
        data        = <<EOH
MARIADB_ROOT_PASSWORD = {{ key "eqpaint/db/root/password" }}
MARIADB_DATABASE      = {{ key "eqpaint/db/name" }}
MARIADB_USER          = {{ key "eqpaint/db/user" }}
MARIADB_PASSWORD      = {{ key "eqpaint/db/password" }}
EOH
      }
    }
  }

  group "wordpress" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "eqpaint-wordpress"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.eqpaint.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.eqpaint.entrypoints=https",
        "traefik.http.routers.eqpaint.tls=true",
      ]
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "busybox:1.36"
        command = "sh"

        args = [
          "-ec",
          <<EOS
if [ -z "$DB_ADDR" ]; then
  echo "DB_ADDR is not set"
  exit 1
fi

host=$(echo "$DB_ADDR" | cut -d: -f1)
port=$(echo "$DB_ADDR" | cut -d: -f2)

echo "Waiting for MariaDB at $host:$port..."

until nc -z "$host" "$port"; do
  sleep 2
done

echo "MariaDB is accepting TCP connections."
EOS
        ]
      }

      template {
        destination = "local/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ range service "eqpaint-db" }}
DB_ADDR={{ .Address }}:{{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = "wordpress:6.5-apache"
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
        change_mode = "restart"
        data        = <<EOH
{{ range service "eqpaint-db" }}
WORDPRESS_DB_HOST={{ .Address }}:{{ .Port }}
{{ end }}
WORDPRESS_DB_USER     = {{ key "eqpaint/db/user" }}
WORDPRESS_DB_PASSWORD = {{ key "eqpaint/db/password" }}
WORDPRESS_DB_NAME     = {{ key "eqpaint/db/name" }}
EOH
      }
    }
  }
}
