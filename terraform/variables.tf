variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vscode_user" {
  description = "UserName for VS code-server"
  type        = string
  default     = "participant"
}

variable "home_folder" {
  description = "Folder to open in VS Code server"
  type        = string
  default     = "/workshop"
}

variable "dev_server_base_path" {
  description = "Base path for the application to be added to Nginx sites-available list"
  type        = string
  default     = "app"
}

variable "dev_server_port" {
  description = "Port for the DevServer"
  type        = number
  default     = 9091
}

variable "vscode_server_port" {
  description = "Port for the VSCode server"
  type        = number
  default     = 9090
}

variable "instance_name" {
  description = "VS code-server EC2 instance name"
  type        = string
  default     = "VSCodeServer"
}
