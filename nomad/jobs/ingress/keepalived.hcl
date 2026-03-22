job "keepalived" {
  datacenters = ["dc1"]
  type        = "service"

  group "odin" {
    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "odin"
    }

    task "keepalived" {
      driver = "docker"

      config {
        image        = "osixia/keepalived:2.3.4"
        network_mode = "host"
        cap_add      = ["NET_ADMIN", "NET_RAW", "NET_BROADCAST"]

        volumes = [
          "local/keepalived.conf:/etc/keepalived/keepalived.conf:ro",
        ]

        args = [
          "--",
          "--dont-fork",
          "--log-console",
          "--log-detail",
          "--dump-conf",
        ]
      }

      template {
        destination = "local/keepalived.conf"
        data        = <<EOF
global_defs {
  router_id odin
  enable_script_security
}

vrrp_instance VI_1 {
  state BACKUP
  interface eno1
  virtual_router_id 51
  priority 150
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass {{ key "keepalived/auth/pass" }}
  }

  unicast_src_ip 192.168.1.100

  unicast_peer {
    192.168.1.101
    192.168.1.102
  }

  virtual_ipaddress {
    192.168.1.240/24
  }
}
EOF
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }

  group "thor" {
    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "thor"
    }

    task "keepalived" {
      driver = "docker"

      config {
        image        = "osixia/keepalived:2.3.4"
        network_mode = "host"
        cap_add      = ["NET_ADMIN", "NET_RAW", "NET_BROADCAST"]

        volumes = [
          "local/keepalived.conf:/etc/keepalived/keepalived.conf:ro",
        ]

        args = [
          "--",
          "--dont-fork",
          "--log-console",
          "--log-detail",
          "--dump-conf",
        ]
      }

      template {
        destination = "local/keepalived.conf"
        data        = <<EOF
global_defs {
  router_id thor
  enable_script_security
}

vrrp_instance VI_1 {
  state BACKUP
  interface eno1
  virtual_router_id 51
  priority 120
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass {{ key "keepalived/auth/pass" }}
  }

  unicast_src_ip 192.168.1.101

  unicast_peer {
    192.168.1.100
    192.168.1.102
  }

  virtual_ipaddress {
    192.168.1.240/24
  }
}
EOF
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }

  group "loki" {
    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "loki"
    }

    task "keepalived" {
      driver = "docker"

      config {
        image        = "osixia/keepalived:2.3.4"
        network_mode = "host"
        cap_add      = ["NET_ADMIN", "NET_RAW", "NET_BROADCAST"]

        volumes = [
          "local/keepalived.conf:/etc/keepalived/keepalived.conf:ro",
        ]

        args = [
          "--",
          "--dont-fork",
          "--log-console",
          "--log-detail",
          "--dump-conf",
        ]
      }

      template {
        destination = "local/keepalived.conf"
        data        = <<EOF
global_defs {
  router_id loki
  enable_script_security
}

vrrp_instance VI_1 {
  state BACKUP
  interface eno1
  virtual_router_id 51
  priority 100
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass {{ key "keepalived/auth/pass" }}
  }

  unicast_src_ip 192.168.1.102

  unicast_peer {
    192.168.1.100
    192.168.1.101
  }

  virtual_ipaddress {
    192.168.1.240/24
  }
}
EOF
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
