job "wazuh" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "wazuh.local.aydenjahola.com"
  }

  group "indexer" {
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
      port "https" {
        to = 9200
      }
    }

    service {
      name = "wazuh-indexer"
      port = "https"

      check {
        name     = "wazuh-indexer-tcp"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "5m"
        }
      }
    }

    task "indexer" {
      driver       = "docker"
      kill_timeout = "30s"

      config {
        image    = "wazuh/wazuh-indexer:4.14.10"
        hostname = "wazuh-indexer"
        # OIDC calls go to Traefik on the keepalived VIP, not out through Cloudflare.
        extra_hosts = ["auth.aydenjahola.com:192.168.1.240"]
        ports       = ["https"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/data:/var/lib/wazuh-indexer:rw",
          "local/opensearch.yml:/usr/share/wazuh-indexer/config/opensearch.yml:ro",
          "secrets/internal_users.yml:/usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml:ro",
          "local/config.yml:/usr/share/wazuh-indexer/config/opensearch-security/config.yml:ro",
          "local/roles_mapping.yml:/usr/share/wazuh-indexer/config/opensearch-security/roles_mapping.yml:ro",
          "secrets/root-ca.pem:/usr/share/wazuh-indexer/config/certs/root-ca.pem:ro",
          "secrets/indexer.pem:/usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem:ro",
          "secrets/indexer-key.pem:/usr/share/wazuh-indexer/config/certs/wazuh.indexer.key:ro",
          "secrets/admin.pem:/usr/share/wazuh-indexer/config/certs/admin.pem:ro",
          "secrets/admin-key.pem:/usr/share/wazuh-indexer/config/certs/admin-key.pem:ro",
        ]
      }

      env {
        TZ                   = "Europe/Dublin"
        OPENSEARCH_JAVA_OPTS = "-Xms1g -Xmx1g"
      }

      template {
        destination = "local/opensearch.yml"
        uid         = 1000
        gid         = 1000
        perms       = "0600"
        data        = <<EOH
network.host: "0.0.0.0"
node.name: "wazuh-indexer"
cluster.name: "wazuh-cluster"
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
discovery.type: single-node
compatibility.override_main_response_version: true
plugins.security.ssl.http.pemcert_filepath: /usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem
plugins.security.ssl.http.pemkey_filepath: /usr/share/wazuh-indexer/config/certs/wazuh.indexer.key
plugins.security.ssl.http.pemtrustedcas_filepath: /usr/share/wazuh-indexer/config/certs/root-ca.pem
plugins.security.ssl.transport.pemcert_filepath: /usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem
plugins.security.ssl.transport.pemkey_filepath: /usr/share/wazuh-indexer/config/certs/wazuh.indexer.key
plugins.security.ssl.transport.pemtrustedcas_filepath: /usr/share/wazuh-indexer/config/certs/root-ca.pem
plugins.security.ssl.http.enabled: true
plugins.security.ssl.transport.enforce_hostname_verification: false
plugins.security.ssl.transport.resolve_hostname: false
plugins.security.ssl.http.enabled_ciphers:
  - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
  - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
  - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
  - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
plugins.security.ssl.http.enabled_protocols:
  - "TLSv1.2"
plugins.security.authcz.admin_dn:
  - "CN=admin,OU=Wazuh,O=Homelab,L=Dublin,C=IE"
plugins.security.check_snapshot_restore_write_privileges: true
plugins.security.enable_snapshot_restore_privilege: true
plugins.security.nodes_dn:
  - "CN=wazuh-indexer,OU=Wazuh,O=Homelab,L=Dublin,C=IE"
plugins.security.restapi.roles_enabled:
  - "all_access"
  - "security_rest_api_access"
plugins.security.system_indices.enabled: true
plugins.security.system_indices.indices: [".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opendistro-notifications-*", ".opendistro-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store"]
plugins.security.allow_default_init_securityindex: true
cluster.routing.allocation.disk.threshold_enabled: false
EOH
      }

      # The opensearch-security files are only read when the security index
      # is first created. After a change, apply it with securityadmin.sh.
      template {
        destination          = "local/config.yml"
        uid                  = 1000
        gid                  = 1000
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
---
_meta:
  type: "config"
  config_version: 2

config:
  dynamic:
    http:
      anonymous_auth_enabled: false
      xff:
        enabled: false
    authc:
      basic_internal_auth_domain:
        description: "Internal users (admin, kibanaserver): break-glass login"
        http_enabled: true
        transport_enabled: true
        order: 0
        http_authenticator:
          type: basic
          challenge: false
        authentication_backend:
          type: intern
      openid_auth_domain:
        description: "Authentik OIDC"
        http_enabled: true
        transport_enabled: true
        order: 1
        http_authenticator:
          type: openid
          challenge: false
          config:
            subject_key: preferred_username
            roles_key: groups
            openid_connect_url: {{ key "authentik/url" }}/application/o/wazuh/.well-known/openid-configuration
        authentication_backend:
          type: noop
EOH
      }

      template {
        destination = "local/roles_mapping.yml"
        uid         = 1000
        gid         = 1000
        perms       = "0600"
        data        = <<EOH
---
_meta:
  type: "rolesmapping"
  config_version: 2

all_access:
  reserved: true
  hidden: false
  backend_roles:
    - "admin"
    - "homelab-admins"
  hosts: []
  users: []
  and_backend_roles: []
  description: "Maps admin and the Authentik homelab-admins group to all_access"

own_index:
  reserved: false
  hidden: false
  backend_roles: []
  hosts: []
  users:
    - "*"
  and_backend_roles: []
  description: "Allow full access to an index named like the username"

readall:
  reserved: true
  hidden: false
  backend_roles:
    - "readall"
  hosts: []
  users: []
  and_backend_roles: []

manage_snapshots:
  reserved: true
  hidden: false
  backend_roles:
    - "snapshotrestore"
  hosts: []
  users: []
  and_backend_roles: []

kibana_server:
  reserved: true
  hidden: false
  backend_roles: []
  hosts: []
  users:
    - "kibanaserver"
  and_backend_roles: []

kibana_user:
  reserved: false
  hidden: false
  backend_roles:
    - "kibanauser"
  hosts: []
  users: []
  and_backend_roles: []
  description: "Maps kibanauser to kibana_user"

manage_wazuh_index:
  reserved: true
  hidden: false
  backend_roles: []
  hosts: []
  users:
    - "kibanaserver"
  and_backend_roles: []
EOH
      }

      template {
        destination          = "secrets/internal_users.yml"
        uid                  = 1000
        gid                  = 1000
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
---
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "{{ key "wazuh/indexer/admin_hash" }}"
  reserved: true
  backend_roles:
    - "admin"
  description: "Admin user"

kibanaserver:
  hash: "{{ key "wazuh/indexer/kibanaserver_hash" }}"
  reserved: true
  description: "Wazuh dashboard server user"
EOH
      }

      dynamic "template" {
        for_each = ["root-ca", "indexer", "indexer-key", "admin", "admin-key"]

        content {
          destination          = "secrets/${template.value}.pem"
          uid                  = 1000
          gid                  = 1000
          perms                = "0600"
          error_on_missing_key = true
          data                 = "{{ key \"wazuh/certs/${template.value}.pem\" }}"
        }
      }

      resources {
        cpu        = 500
        memory     = 1536
        memory_max = 2048
      }
    }
  }

  group "manager" {
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
      port "events" {
        static = 1514
        to     = 1514
      }

      port "enrollment" {
        static = 1515
        to     = 1515
      }

      port "api" {
        to = 55000
      }
    }

    service {
      name = "wazuh-manager"
      port = "events"

      check {
        name     = "wazuh-manager-events"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "5m"
        }
      }
    }

    service {
      name = "wazuh-manager-api"
      port = "api"

      check {
        name     = "wazuh-manager-api"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "5m"
        }
      }
    }

    task "manager" {
      driver       = "docker"
      kill_timeout = "30s"

      config {
        image    = "wazuh/wazuh-manager:4.14.10"
        hostname = "wazuh-manager"
        ports    = ["events", "enrollment", "api"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/api-configuration:/var/ossec/api/configuration:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/etc:/var/ossec/etc:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/logs:/var/ossec/logs:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/queue:/var/ossec/queue:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/multigroups:/var/ossec/var/multigroups:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/integrations:/var/ossec/integrations:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/active-response:/var/ossec/active-response/bin:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/agentless:/var/ossec/agentless:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/wodles:/var/ossec/wodles:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/filebeat-etc:/etc/filebeat:rw",
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}/filebeat-var:/var/lib/filebeat:rw",
          "secrets/config-mount:/wazuh-config-mount:ro",
          "secrets/root-ca.pem:/etc/ssl/root-ca.pem:ro",
          "secrets/manager.pem:/etc/ssl/filebeat.pem:ro",
          "secrets/manager-key.pem:/etc/ssl/filebeat.key:ro",
        ]
      }

      env {
        TZ                             = "Europe/Dublin"
        INDEXER_USERNAME               = "admin"
        API_USERNAME                   = "wazuh-wui"
        FILEBEAT_SSL_VERIFICATION_MODE = "full"
        SSL_CERTIFICATE_AUTHORITIES    = "/etc/ssl/root-ca.pem"
        SSL_CERTIFICATE                = "/etc/ssl/filebeat.pem"
        SSL_KEY                        = "/etc/ssl/filebeat.key"
      }

      # The image seds INDEXER_URL into filebeat.yml as `hosts: [$INDEXER_URL]`,
      # so it must keep its double quotes.
      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
INDEXER_PASSWORD = {{ key "wazuh/indexer/admin_password" }}
API_PASSWORD     = {{ key "wazuh/api/password" }}
{{- range service "wazuh-indexer" }}
INDEXER_URL      = '"https://{{ .Address }}:{{ .Port }}"'
{{- end }}
EOH
      }

      template {
        destination = "secrets/config-mount/etc/ossec.conf"
        perms       = "0640"
        data        = file("jobs/security/wazuh/ossec.conf")
      }

      template {
        destination = "secrets/config-mount/etc/rules/local_rules.xml"
        perms       = "0640"
        data        = file("jobs/security/wazuh/local_rules.xml")
      }

      template {
        destination          = "secrets/config-mount/etc/authd.pass"
        perms                = "0640"
        error_on_missing_key = true
        data                 = "{{ key \"wazuh/authd/password\" }}"
      }

      dynamic "template" {
        for_each = ["root-ca", "manager", "manager-key"]

        content {
          destination          = "secrets/${template.value}.pem"
          gid                  = 999
          perms                = "0640"
          error_on_missing_key = true
          data                 = "{{ key \"wazuh/certs/${template.value}.pem\" }}"
        }
      }

      resources {
        cpu        = 500
        memory     = 1024
        memory_max = 3072
      }
    }

    # Ships alerts to Loki through Alloy as {task="wazuh-alerts"}. It reads the
    # manager task's log folder, so the task name is spelled out here.
    task "wazuh-alerts" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image   = "busybox:1.37.0"
        command = "tail"
        args    = ["-n", "0", "-F", "/logs/alerts/alerts.json"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/manager/logs:/logs:ro",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 64
      }
    }
  }

  group "dashboard" {
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
        to = 5601
      }
    }

    service {
      name = "wazuh-dashboard"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.wazuh.entrypoints=https",
        "traefik.http.routers.wazuh.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.wazuh.middlewares=lan-only@file",
      ]

      check {
        name     = "wazuh-dashboard-http"
        type     = "http"
        path     = "/app/login"
        interval = "30s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "5m"
        }
      }
    }

    task "dashboard" {
      driver = "docker"

      config {
        image    = "wazuh/wazuh-dashboard:4.14.10"
        hostname = "wazuh-dashboard"
        # OIDC calls go to Traefik on the keepalived VIP, not out through Cloudflare.
        extra_hosts = ["auth.aydenjahola.com:192.168.1.240"]
        ports       = ["http"]

        volumes = [
          "secrets/opensearch_dashboards.yml:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml:ro",
          "secrets/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:rw",
          "secrets/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem:ro",
        ]
      }

      env {
        TZ                 = "Europe/Dublin"
        DASHBOARD_USERNAME = "kibanaserver"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
DASHBOARD_PASSWORD = {{ key "wazuh/indexer/kibanaserver_password" }}
EOH
      }

      template {
        destination          = "secrets/opensearch_dashboards.yml"
        uid                  = 1000
        gid                  = 1000
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
server.host: 0.0.0.0
server.port: 5601
server.ssl.enabled: false
opensearch.hosts: [{{ range service "wazuh-indexer" }}"https://{{ .Address }}:{{ .Port }}"{{ end }}]
opensearch.ssl.verificationMode: full
opensearch.ssl.certificateAuthorities: ["/usr/share/wazuh-dashboard/certs/root-ca.pem"]
opensearch.requestHeadersWhitelist: ["securitytenant","Authorization"]
opensearch_security.multitenancy.enabled: false
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
opensearch_security.cookie.secure: true
opensearch_security.cookie.ttl: 900000
opensearch_security.session.ttl: 900000
opensearch_security.session.keepalive: true
uiSettings.overrides.defaultRoute: /app/wz-home
opensearch_security.auth.type: ["openid", "basicauth"]
opensearch_security.auth.multiple_auth_enabled: true
opensearch_security.openid.connect_url: "{{ key "authentik/url" }}/application/o/wazuh/.well-known/openid-configuration"
opensearch_security.openid.client_id: {{ key "authentik/oidc/wazuh/client_id" | toJSON }}
opensearch_security.openid.client_secret: {{ key "authentik/oidc/wazuh/client_secret" | toJSON }}
opensearch_security.openid.base_redirect_url: "https://{{ env "NOMAD_META_domain" }}"
opensearch_security.openid.scope: "openid profile email"
opensearch_security.openid.logout_url: "{{ key "authentik/url" }}/application/o/wazuh/end-session/"
EOH
      }

      template {
        destination          = "secrets/wazuh.yml"
        uid                  = 1000
        gid                  = 1000
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
hosts:
  - 1513629884013:
{{- range service "wazuh-manager-api" }}
      url: "https://{{ .Address }}"
      port: {{ .Port }}
{{- end }}
      username: wazuh-wui
      password: {{ key "wazuh/api/password" | toJSON }}
      run_as: true
EOH
      }

      template {
        destination          = "secrets/root-ca.pem"
        uid                  = 1000
        gid                  = 1000
        perms                = "0600"
        error_on_missing_key = true
        data                 = "{{ key \"wazuh/certs/root-ca.pem\" }}"
      }

      resources {
        cpu        = 200
        memory     = 512
        memory_max = 1024
      }
    }

    # Imports the saved objects in wazuh/dashboards (from generate.py) and the
    # ISM retention policy on every start.
    task "import-dashboards" {
      driver = "docker"

      lifecycle {
        hook = "poststart"
      }

      config {
        image   = "curlimages/curl:8.23.0"
        command = "/bin/sh"
        args    = ["/local/import.sh"]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination          = "secrets/.env"
        env                  = true
        perms                = "0600"
        error_on_missing_key = true
        data                 = <<EOH
ADMIN_PASSWORD = {{ key "wazuh/indexer/admin_password" }}
{{- range service "wazuh-indexer" }}
INDEXER_URL    = https://{{ .Address }}:{{ .Port }}
{{- end }}
EOH
      }

      template {
        destination          = "secrets/root-ca.pem"
        perms                = "0644"
        error_on_missing_key = true
        data                 = "{{ key \"wazuh/certs/root-ca.pem\" }}"
      }

      template {
        destination = "local/import.sh"
        perms       = "0755"
        data        = file("jobs/security/wazuh/import.sh")
      }

      template {
        destination = "local/ism-retention.json"
        data        = file("jobs/security/wazuh/ism-retention.json")
      }

      dynamic "template" {
        for_each = fileset("jobs/security/wazuh/dashboards", "*.ndjson")

        content {
          destination = "local/dashboards/${template.value}"
          data        = file("jobs/security/wazuh/dashboards/${template.value}")
        }
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 64
      }
    }
  }
}
