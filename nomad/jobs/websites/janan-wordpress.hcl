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

        args = [
          "--innodb-buffer-pool-size=512M",
          "--innodb-flush-log-at-trx-commit=2",
          "--max-connections=100",
          "--query-cache-type=0",
        ]
      }

      resources {
        cpu    = 750
        memory = 1024
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"

        data = <<EOH
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

      port "fpm" {
        to = 9000
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

        data = <<EOH
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

    task "redis" {
      driver = "docker"

      config {
        image = "redis:7-alpine"
        args  = ["--maxmemory", "128mb", "--maxmemory-policy", "allkeys-lru", "--save", "", "--appendonly", "no"]
      }

      resources {
        cpu    = 100
        memory = 160
      }
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = "wordpress:7.0-php8.3-fpm"

        ports = ["fpm"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/wp_data:/var/www/html:rw",
          "local/custom-php.ini:/usr/local/etc/php/conf.d/zz-custom.ini:ro",
          "local/fpm-pool-tuning.conf:/usr/local/etc/php-fpm.d/www.conf:ro",
        ]
      }

      resources {
        cpu    = 700
        memory = 896
      }

      service {
        name = "janan-fpm"
        port = "fpm"

        check {
          name     = "php-fpm-tcp"
          type     = "tcp"
          interval = "10s"
          timeout  = "3s"
        }
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"

        data = <<EOH
{{ range service "janan-db" }}
WORDPRESS_DB_HOST={{ .Address }}:{{ .Port }}
{{ end }}
WORDPRESS_DB_USER     = {{ key "janan/db/user" }}
WORDPRESS_DB_PASSWORD = {{ key "janan/db/password" }}
WORDPRESS_DB_NAME     = {{ key "janan/db/name" }}
EOH
      }

      env {
        WORDPRESS_CONFIG_EXTRA = <<-EOC
          define('WP_REDIS_HOST', '127.0.0.1');
          define('WP_REDIS_PORT', 6379);
          define('WP_CACHE', true);
          define('WP_MEMORY_LIMIT', '256M');
        EOC
      }

      template {
        destination = "local/custom-php.ini"
        change_mode = "restart"

        data = <<EOH
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.save_comments=1
opcache.fast_shutdown=1

realpath_cache_size=4096K
realpath_cache_ttl=600

memory_limit=256M
max_execution_time=120
upload_max_filesize=64M
post_max_size=64M
max_input_vars=3000
EOH
      }

      template {
        destination = "local/fpm-pool-tuning.conf"
        change_mode = "restart"

        data = <<EOH
[www]
user = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 16
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500
pm.process_idle_timeout = 10s
EOH
      }
    }

    task "nginx" {
      driver = "docker"

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
        memory = 256
      }

      template {
        destination = "local/default.conf"
        change_mode = "restart"

        data = <<EOH
fastcgi_cache_path /tmp/nginx-fcgi-cache levels=1:2 keys_zone=WORDPRESS:100m inactive=60m max_size=512m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
fastcgi_cache_use_stale error timeout updating invalid_header http_500;

gzip on;
gzip_vary on;
gzip_comp_level 5;
gzip_min_length 256;
gzip_types application/javascript application/json application/xml text/css text/javascript text/plain text/xml image/svg+xml;

server {
    listen 80 default_server;
    server_name {{ env "NOMAD_META_domain" }} www.{{ env "NOMAD_META_domain" }} _;
    root /var/www/html;
    index index.php;

    client_max_body_size 64m;

    set $skip_cache 0;
    if ($request_method = POST) { set $skip_cache 1; }
    if ($query_string != "") { set $skip_cache 1; }
    if ($request_uri ~* "/wp-admin/|/wp-json/|wp-login.php|/xmlrpc.php") { set $skip_cache 1; }
    if ($http_cookie ~* "comment_author|wordpress_logged_in|wp-postpass|woocommerce_items_in_cart") { set $skip_cache 1; }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; }

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass {{ range service "janan-fpm" }}{{ .Address }}:{{ .Port }}{{ end }};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 60m;
        fastcgi_cache_valid 404 1m;
        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        add_header X-FastCGI-Cache $upstream_cache_status;
    }

    location ~* /wp-content/uploads/.*\.php$ { deny all; }
    location ~ /\.ht { deny all; }
}
EOH
      }
    }
  }
}
