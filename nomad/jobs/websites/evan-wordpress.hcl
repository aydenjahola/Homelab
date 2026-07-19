job "eqpaint-wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "eqpaintingsolutions.com.au"
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
          "local/tuning.cnf:/etc/mysql/conf.d/tuning.cnf:ro",
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      template {
        destination = "local/tuning.cnf"
        change_mode = "restart"

        data = <<EOH
[mysqld]
innodb_buffer_pool_size=512M
innodb_log_file_size=128M
query_cache_type=0
max_connections=100
EOH
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"

        data = <<EOH
MARIADB_ROOT_PASSWORD = {{ key "eqpaint/db/root/password" }}
MARIADB_DATABASE      = {{ key "eqpaint/db/name" }}
MARIADB_USER          = {{ key "eqpaint/db/user" }}
MARIADB_PASSWORD      = {{ key "eqpaint/db/password" }}
EOH
      }
    }
  }

  group "cache" {
    count = 1

    network {
      port "redis" {
        to = 6379
      }
    }

    service {
      name = "eqpaint-redis"
      port = "redis"

      check {
        name     = "redis-tcp"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "redis:7-alpine"
        ports = ["redis"]
        args  = ["--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/redis_data:/data:rw",
        ]
      }

      resources {
        cpu    = 100
        memory = 256
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
        "traefik.http.routers.eqpaint-www.rule=Host(`www.${NOMAD_META_domain}`)",
        "traefik.http.routers.eqpaint-www.entrypoints=https",
        "traefik.http.routers.eqpaint-www.tls=true",
        "traefik.http.routers.eqpaint-www.middlewares=eqpaint-www-redirect",
        "traefik.http.middlewares.eqpaint-www-redirect.redirectregex.regex=^https://www\\.(.*)",
        "traefik.http.middlewares.eqpaint-www-redirect.redirectregex.replacement=https://$${1}",
        "traefik.http.middlewares.eqpaint-www-redirect.redirectregex.permanent=true",
        "traefik.http.middlewares.eqpaint-bodylimit.buffering.maxRequestBodyBytes=0",
        "traefik.http.middlewares.eqpaint-bodylimit.buffering.memRequestBodyBytes=0",
        "traefik.http.middlewares.eqpaint-compress.compress=true",
        "traefik.http.routers.eqpaint.middlewares=eqpaint-bodylimit,eqpaint-compress",
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

        data = <<EOH
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

    task "php-fpm" {
      driver = "docker"

      config {
        image = "wordpress:php8.3-fpm"

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/wp_data:/var/www/html:rw",
          "local/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini:ro",
          "local/opcache.ini:/usr/local/etc/php/conf.d/opcache.ini:ro",
          "local/www.conf:/usr/local/etc/php-fpm.d/zz-www.conf:ro",
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      template {
        destination = "local/uploads.ini"
        change_mode = "restart"

        data = <<EOH
file_uploads = On
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
EOH
      }

      template {
        destination = "local/opcache.ini"
        change_mode = "restart"

        data = <<EOH
opcache.enable=1
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
EOH
      }

      template {
        destination = "local/www.conf"
        change_mode = "restart"

        data = <<EOH
[www]
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500
EOH
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"

        data = <<EOH
{{ range service "eqpaint-db" }}
WORDPRESS_DB_HOST={{ .Address }}:{{ .Port }}
{{ end }}
WORDPRESS_DB_USER     = {{ key "eqpaint/db/user" }}
WORDPRESS_DB_PASSWORD = {{ key "eqpaint/db/password" }}
WORDPRESS_DB_NAME     = {{ key "eqpaint/db/name" }}
{{ range service "eqpaint-redis" }}
WORDPRESS_CONFIG_EXTRA=define('WP_REDIS_HOST', '{{ .Address }}'); define('WP_REDIS_PORT', {{ .Port }}); define('WP_CACHE', true);
{{ end }}
EOH
      }
    }

    task "nginx" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image = "nginx:1.27-alpine"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/wp_data:/var/www/html:ro",
          "local/default.conf:/etc/nginx/conf.d/default.conf:ro",
        ]
      }

      resources {
        cpu    = 200
        memory = 128
      }

      template {
        destination = "local/default.conf"
        change_mode = "restart"

        data = <<EOH
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php;

    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2?|svg)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /wp-config.php {
        deny all;
    }
}
EOH
      }
    }
  }
}
