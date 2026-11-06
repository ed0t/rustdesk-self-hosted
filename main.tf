terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# 1. Create the Lightsail Instance
resource "aws_lightsail_instance" "rustdesk_server" {
  name              = var.instance_name
  availability_zone = "${var.region}a"
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  user_data = <<-EOF
              #!/bin/bash
              # Install Docker
              apt-get update
              apt-get install -y docker.io docker-compose-v2
              
              # Setup directory
              mkdir -p /home/ubuntu/rustdesk
              cd /home/ubuntu/rustdesk

              # Create the compose file
              cat <<EOT > docker-compose.yml
              services:
                hbbs:
                  container_name: hbbs
                  image: rustdesk/rustdesk-server:${var.rustdesk_server_version}
                  command: hbbs -r ${aws_lightsail_static_ip.rustdesk_ip.ip_address}:21117
                  volumes:
                    - ./data:/root
                  network_mode: "host"
                  restart: unless-stopped
                hbbr:
                  container_name: hbbr
                  image: rustdesk/rustdesk-server:${var.rustdesk_server_version}
                  command: hbbr -k _
                  volumes:
                    - ./data:/root
                  network_mode: "host"
                  restart: unless-stopped
              EOT
              
              docker compose up -d
              EOF

  # user_data only runs on first boot; changing it would replace the
  # instance and regenerate the RustDesk key, so don't act on edits to it.
  lifecycle {
    ignore_changes = [user_data]
  }
}

# 2. Assign the Static IP (Ensures the IP never changes)
resource "aws_lightsail_static_ip" "rustdesk_ip" {
  name = var.static_ip_name
}

resource "aws_lightsail_static_ip_attachment" "rustdesk_ip_attach" {
  static_ip_name = aws_lightsail_static_ip.rustdesk_ip.name
  instance_name  = aws_lightsail_instance.rustdesk_server.name
}

# 3. Open Firewall Ports
resource "aws_lightsail_instance_public_ports" "rustdesk_firewall" {
  instance_name = aws_lightsail_instance.rustdesk_server.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 21115
    to_port   = 21117
  }

  port_info {
    protocol  = "udp"
    from_port = 21116
    to_port   = 21116
  }
}

# Outputs read by ./rdesk and used in your RustDesk client
output "rustdesk_server_ip" {
  value = aws_lightsail_static_ip.rustdesk_ip.ip_address
}

output "region" {
  value = var.region
}

output "instance_name" {
  value = aws_lightsail_instance.rustdesk_server.name
}
