job "jenkins" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jenkins.aydenjahola.com"
  }

  group "controller" {
    count = 1

    network {
      port "http" {
        to = 8080
      }

      port "agent" {
        to = 50000
      }
    }

    service {
      name = "jenkins"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jenkins.rule=Host(`${NOMAD_META_domain}`)",
        "traefik.http.routers.jenkins.entrypoints=https",
      ]
    }

    service {
      name = "jenkins-agent"
      port = "agent"
    }

    task "plugins" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "jenkins/jenkins:lts-jdk21"
        command = "bash"
        args = [
          "-lc",
          "export PATH=/opt/java/openjdk/bin:$PATH; java -version; /usr/bin/jenkins-plugin-cli --plugin-file /local/plugins.txt --plugin-download-directory /var/jenkins_home/plugins"
        ]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/jenkins_home:/var/jenkins_home",
          "local/plugins.txt:/local/plugins.txt",
        ]
      }

      template {
        destination = "local/plugins.txt"
        data        = <<EOH
configuration-as-code
git
workflow-aggregator
credentials-binding
pipeline-stage-view
github
blueocean
nomad
EOH
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }

    task "jenkins" {
      driver = "docker"

      config {
        image = "jenkins/jenkins:lts-jdk21"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/jenkins_home:/var/jenkins_home",
          "local/jenkins.yaml:/var/jenkins_home/jenkins.yaml",
        ]
      }

      env {
        CASC_JENKINS_CONFIG = "/var/jenkins_home/jenkins.yaml"
      }

      template {
        destination = "local/jenkins.env"
        env         = true
        data        = <<EOH
jenkins_admin_user     = {{ key "jenkins/admin/user" }}
jenkins_admin_password = {{ key "jenkins/admin/password" }}
EOH
      }

      template {
        destination = "local/jenkins.yaml"
        data        = <<EOH
jenkins:
  systemMessage: "Jenkins bootstrapped via JCasC"
  numExecutors: 2

  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${jenkins_admin_user}"
          password: "${jenkins_admin_password}"

  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

unclassified:
  location:
    url: "https://{{ env "NOMAD_META_domain" }}/"
EOH
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
