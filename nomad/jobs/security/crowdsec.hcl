job "crowdsec" {
  datacenters = ["dc1"]
  type        = "service"

  group "crowdsec" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = false
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

    network {
      port "lapi" {
        to = 8080
      }

      port "metrics" {
        to = 6060
      }
    }

    service {
      name = "crowdsec"
      port = "lapi"

      check {
        name     = "crowdsec-health"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "3m"
        }
      }
    }

    service {
      name = "crowdsec-metrics"
      port = "metrics"
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "postgres:17-alpine"
        command = "sh"

        args = [
          "-c",
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "crowdsec/db/user" }}
DB_NAME = {{ key "crowdsec/db/name" }}
{{ range service "crowdsec-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 50
        memory     = 64
        memory_max = 128
      }
    }

    task "crowdsec" {
      driver = "docker"

      config {
        image = "crowdsecurity/crowdsec:v1.8.2"
        ports = ["lapi", "metrics"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/config:/etc/crowdsec:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/var/lib/crowdsec/data:rw",
          "local/acquis.yaml:/etc/crowdsec/acquis.yaml:ro",
          "local/config.yaml.local:/etc/crowdsec/config.yaml.local:ro",
        ]
      }

      env {
        TZ          = "Europe/Dublin"
        COLLECTIONS = "crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/whitelist-good-actors"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
BOUNCER_KEY_traefik = {{ key "crowdsec/bouncer/traefik" }}
EOH
      }

      template {
        destination          = "local/config.yaml.local"
        perms                = "0644"
        error_on_missing_key = true
        data                 = <<EOH
db_config:
  type: postgresql
  user: {{ key "crowdsec/db/user" }}
  password: {{ key "crowdsec/db/password" | toJSON }}
  db_name: {{ key "crowdsec/db/name" }}
{{- range service "crowdsec-db" }}
  host: {{ .Address }}
  port: {{ .Port }}
{{- end }}
  sslmode: disable
prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0
  listen_port: 6060
EOH
      }

      template {
        destination = "local/acquis.yaml"
        data        = <<EOH
source: loki
url: http://{{ range service "loki" }}{{ .Address }}:{{ .Port }}{{ end }}
query: '{task="traefik"} |= "RequestHost"'
labels:
  type: traefik
EOH
      }

      resources {
        cpu        = 200
        memory     = 256
        memory_max = 768
      }
    }
  }

  group "db" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = false
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }

    network {
      port "db" {
        to = 5432
      }
    }

    service {
      name = "crowdsec-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "300s"
          ignore_warnings = false
        }
      }
    }

    task "db" {
      driver       = "docker"
      kill_signal  = "SIGINT"
      kill_timeout = "30s"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}-pg17:/var/lib/postgresql/data:rw",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "local/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
POSTGRES_USER     = {{ key "crowdsec/db/user" }}
POSTGRES_PASSWORD = {{ key "crowdsec/db/password" }}
POSTGRES_DB       = {{ key "crowdsec/db/name" }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 512
      }
    }
  }
}
