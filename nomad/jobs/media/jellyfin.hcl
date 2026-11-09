job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellyfin.local.aydenjahola.com"
  }

  group "jellyfin" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
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
      port "http" {
        to = 8096
      }
    }

    service {
      name = "jellyfin"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyfin.entrypoints=https",
        "traefik.http.routers.jellyfin.rule=Host(`${NOMAD_META_domain}`)",
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
          "until pg_isready -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\"; do echo waiting for db; sleep 2; done"
        ]
      }

      template {
        destination          = "local/.env"
        env                  = true
        error_on_missing_key = true
        data                 = <<EOH
DB_USER = {{ key "jellyfin/db/user" }}
DB_NAME = {{ key "jellyfin/db/name" }}
{{ range service "jellyfin-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{ end }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }
    }

    task "jellyfin" {
      driver = "docker"

      config {
        image = "ghcr.io/jpvenson/jellyfin.pgsql:10.11.8-1"
        ports = ["http"]

        group_add = ["109", "44"]

        devices = [
          {
            host_path      = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/data:/config:rw",
          "/storage/jellyfin/tv:/data/tvshows:rw",
          "/storage/jellyfin/movies:/data/movies:rw",
          "/etc/localtime:/etc/localtime:ro",
          # Managed by Nomad (read-only): plugin UI saves and auto-linking new SSO users fail; add users to CanonicalLinks below.
          "local/SSO-Auth.xml:/config/plugins/configurations/SSO-Auth.xml:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true

        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
TZ                          = Europe/Dublin
JELLYFIN_PublishedServerUrl = https://${NOMAD_META_domain}

POSTGRES_DB       = {{ key "jellyfin/db/name" }}
POSTGRES_USER     = {{ key "jellyfin/db/user" }}
POSTGRES_PASSWORD = {{ key "jellyfin/db/password" }}

{{ range service "jellyfin-db" }}
POSTGRES_HOST={{ .Address }}
POSTGRES_PORT={{ .Port }}
{{ end }}
EOH
      }

      template {
        destination          = "local/SSO-Auth.xml"
        change_mode          = "restart"
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
<?xml version="1.0" encoding="utf-8"?>
<PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <SamlConfigs />
  <OidConfigs>
    <item>
      <key><string>authentik</string></key>
      <value>
        <PluginConfiguration>
          <OidEndpoint>{{ key "authentik/url" }}/application/o/jellyfin/</OidEndpoint>
          <OidClientId>{{ key "authentik/oidc/jellyfin/client_id" }}</OidClientId>
          <OidSecret>{{ key "authentik/oidc/jellyfin/client_secret" }}</OidSecret>
          <Enabled>true</Enabled>
          <EnableAuthorization>true</EnableAuthorization>
          <EnableAllFolders>true</EnableAllFolders>
          <EnabledFolders />
          <Roles><string>homelab-admins</string></Roles>
          <AdminRoles><string>homelab-admins</string></AdminRoles>
          <RoleClaim>groups</RoleClaim>
          <EnableFolderRoles>false</EnableFolderRoles>
          <FolderRoleMappings />
          <OidScopes><string>openid</string><string>profile</string><string>email</string></OidScopes>
          <DefaultProvider>Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider</DefaultProvider>
          <SchemeOverride>https</SchemeOverride>
          <CanonicalLinks>
            <item>
              <key><string>ayden</string></key>
              <value><guid>49365b3a-5fb8-4a86-a97f-baef0d8fe245</guid></value>
            </item>
          </CanonicalLinks>
        </PluginConfiguration>
      </value>
    </item>
  </OidConfigs>
</PluginConfiguration>
EOH
      }

      resources {
        cpu        = 1000
        memory     = 1856
        memory_max = 2048
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
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
      name = "jellyfin-db"
      port = "db"

      check {
        name     = "postgres-ready"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data:rw",
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
POSTGRES_USER     = {{ key "jellyfin/db/user" }}
POSTGRES_DB       = {{ key "jellyfin/db/name" }}
POSTGRES_PASSWORD = {{ key "jellyfin/db/password" }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 128
        memory_max = 1024
      }
    }
  }
}
