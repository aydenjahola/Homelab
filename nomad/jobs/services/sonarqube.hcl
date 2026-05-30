job "sonarqube" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sonarqube.local.aydenjahola.com"
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 9000
      }
    }

    service {
      name = "sonarqube"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.sonarqube.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.sonarqube.entrypoints=https",
      ]
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
          "while ! pg_isready -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER}; do echo 'Waiting for SonarQube DB...'; sleep 2; done; echo 'DB is ready!'",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
{{ range service "sonarqube-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}

DB_USER={{ key "sonarqube/db/user" }}
EOH
      }

      resources {
        cpu    = 50
        memory = 128
      }
    }

    task "sysctl-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        destination = "local/init.sh"
        perms       = "0755"
        data        = <<EOF
#!/bin/sh
set -e

# Elasticsearch / SonarQube requirements
sysctl -w vm.max_map_count=524288
sysctl -w fs.file-max=131072

echo "vm.max_map_count=$(sysctl -n vm.max_map_count)"
echo "fs.file-max=$(sysctl -n fs.file-max)"
EOF
      }

      config {
        image   = "alpine:3.20"
        command = "sh"
        args    = ["-e", "${NOMAD_TASK_DIR}/init.sh"]

        privileged = true
        pid_mode   = "host"
      }

      resources {
        cpu    = 20
        memory = 32
      }
    }

    task "sonarqube" {
      driver = "docker"

      config {
        image = "sonarqube:community"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/opt/sonarqube/data",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/extensions:/opt/sonarqube/extensions",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/logs:/opt/sonarqube/logs",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
{{ range service "sonarqube-db" }}
SONAR_JDBC_URL=jdbc:postgresql://{{ .Address }}:{{ .Port }}/{{ key "sonarqube/db/name" }}
{{ end }}

SONAR_JDBC_USERNAME = {{ key "sonarqube/db/user" }}
SONAR_JDBC_PASSWORD = {{ key "sonarqube/db/password" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 3072
      }
    }
  }

  group "database" {
    count = 1

    network {
      port "db" {
        to = 5432
      }
    }

    update {
      max_parallel = 0
      auto_revert  = false
    }

    task "sonarqube-db" {
      driver         = "docker"
      kill_signal    = "SIGTERM"

      service {
        name = "sonarqube-db"
        port = "db"
      }

      config {
        image = "postgres:17-alpine"
        ports = ["db"]
        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_DB       = {{ key "sonarqube/db/name" }}
POSTGRES_USER     = {{ key "sonarqube/db/user" }}
POSTGRES_PASSWORD = {{ key "sonarqube/db/password" }}
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
