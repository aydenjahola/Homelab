job "janan-wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "katyaphone.com.au"
  }

  group "db" {
    count = 1

    network {
      port "db" {
        to = 3306
      }
    }

    service {
      name = "janan-db"
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
MARIADB_ROOT_PASSWORD = {{ key "janan/db/root/password" }}
MARIADB_DATABASE      = {{ key "janan/db/name" }}
MARIADB_USER          = {{ key "janan/db/user" }}
MARIADB_PASSWORD      = {{ key "janan/db/password" }}
EOH
      }
    }
  }

  group "janan" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "janan-wordpress"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.janan.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.janan.entrypoints=https",
        "traefik.http.routers.janan.tls=true",
        "traefik.http.routers.janan-www.rule=Host(`www.${NOMAD_META_domain}`)",
        "traefik.http.routers.janan-www.entrypoints=https",
        "traefik.http.routers.janan-www.tls=true",
        "traefik.http.routers.janan-www.middlewares=janan-www-redirect",
        "traefik.http.middlewares.janan-www-redirect.redirectregex.regex=^https://www\\.(.*)",
        "traefik.http.middlewares.janan-www-redirect.redirectregex.replacement=https://$${1}",
        "traefik.http.middlewares.janan-www-redirect.redirectregex.permanent=true",
        "traefik.http.middlewares.janan-bodylimit.buffering.maxRequestBodyBytes=0",
        "traefik.http.middlewares.janan-bodylimit.buffering.memRequestBodyBytes=0",
        "traefik.http.routers.janan.middlewares=janan-bodylimit",
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
{{ range service "janan-db" }}
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
{{ range service "janan-db" }}
WORDPRESS_DB_HOST={{ .Address }}:{{ .Port }}
{{ end }}
WORDPRESS_DB_USER     = {{ key "janan/db/user" }}
WORDPRESS_DB_PASSWORD = {{ key "janan/db/password" }}
WORDPRESS_DB_NAME     = {{ key "janan/db/name" }}
EOH
      }
    }
  }
}

