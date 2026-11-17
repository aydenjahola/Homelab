job "suricata" {
  datacenters = ["dc1"]
  type        = "system"

  group "suricata" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "30s"
      mode     = "fail"
    }

    task "suricata" {
      driver = "docker"

      config {
        image        = "jasonish/suricata:8.0.8"
        network_mode = "host"
        cap_add      = ["net_admin", "net_raw"]
        entrypoint   = ["/bin/sh", "-c"]
        args = [<<SCRIPT
set -e
suricata-update -q --no-test --no-reload --disable-conf /local/disable.conf
(while sleep 86400; do
  suricata-update -q --no-test --no-reload --disable-conf /local/disable.conf && suricatasc -c ruleset-reload-nonblocking || true
done) &
exec suricata -c /local/suricata.yaml --af-packet=eno1 -v
SCRIPT
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      # Decoder and protocol-quirk rules that only fire on normal LAN and internal app traffic.
      template {
        destination = "local/disable.conf"
        data        = <<EOH
2200121
2221033
2221036
EOH
      }

      template {
        destination = "local/suricata.yaml"
        data        = <<EOH
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[192.168.1.0/24,172.16.0.0/12]"
    EXTERNAL_NET: "!$HOME_NET"
    HTTP_SERVERS: "$HOME_NET"
    SMTP_SERVERS: "$HOME_NET"
    SQL_SERVERS: "$HOME_NET"
    DNS_SERVERS: "$HOME_NET"
    TELNET_SERVERS: "$HOME_NET"
    AIM_SERVERS: "$EXTERNAL_NET"
    DC_SERVERS: "$HOME_NET"
    DNP3_SERVER: "$HOME_NET"
    DNP3_CLIENT: "$HOME_NET"
    MODBUS_CLIENT: "$HOME_NET"
    MODBUS_SERVER: "$HOME_NET"
    ENIP_CLIENT: "$HOME_NET"
    ENIP_SERVER: "$HOME_NET"
  port-groups:
    HTTP_PORTS: "80"
    SHELLCODE_PORTS: "!80"
    ORACLE_PORTS: 1521
    SSH_PORTS: 22
    DNP3_PORTS: 20000
    MODBUS_PORTS: 502
    FILE_DATA_PORTS: "[$HTTP_PORTS,110,143]"
    FTP_PORTS: 21
    GENEVE_PORTS: 6081
    VXLAN_PORTS: 4789
    TEREDO_PORTS: 3544

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules
classification-file: /etc/suricata/classification.config
reference-config-file: /etc/suricata/reference.config
default-log-dir: /var/log/suricata/

stats:
  enabled: yes
  interval: 60

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /dev/stdout
      community-id: yes
      types:
        - alert:
            tagged-packets: no
        - anomaly:
            enabled: yes
        - dns
        - tls
        - ssh
        - stats:
            totals: yes
            threads: no
            deltas: yes

af-packet:
  - interface: eno1
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes
    use-mmap: yes
    bpf-filter: "not port 2049"

unix-command:
  enabled: yes
  filename: /var/run/suricata/suricata-command.socket

logging:
  default-log-level: notice
  outputs:
    - console:
        enabled: yes
EOH
      }

      resources {
        cpu        = 500
        memory     = 1024
        memory_max = 2048
      }
    }
  }
}
