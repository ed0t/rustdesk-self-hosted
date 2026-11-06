variable "region" {
  description = "AWS region to run the server in. Pick one close to you and the people you support."
  type        = string
  default     = "eu-west-2"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "rustdesk-support-server"
}

variable "static_ip_name" {
  description = "Name of the Lightsail static IP."
  type        = string
  default     = "rustdesk-static-ip"
}

variable "bundle_id" {
  description = "Lightsail plan. nano_3_0 is the smallest and is plenty for a few RustDesk clients."
  type        = string
  default     = "nano_3_0"
}

variable "blueprint_id" {
  description = "Lightsail OS image."
  type        = string
  default     = "ubuntu_24_04"
}

variable "rustdesk_server_version" {
  description = "rustdesk/rustdesk-server Docker image tag. Only used when the server is first created."
  type        = string
  default     = "1.1.16"
}
