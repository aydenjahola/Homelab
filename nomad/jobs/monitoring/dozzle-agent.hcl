job "dozzle-agent" {
  datacenters = ["dc1"]
  type        = "system"

  group "dozzle-agent" {
    network {
      port "agent" {
        static = 7007
        to     = 7007
      }
    }

    service {
      name = "dozzle-agent"
      port = "agent"

      check {
        name     = "dozzle-agent-tcp"
        type     = "tcp"
        port     = "agent"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "dozzle-agent" {
      driver = "docker"

      config {
        image   = "amir20/dozzle:latest"
        command = "agent"
        ports   = ["agent"]

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro",
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
