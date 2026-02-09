variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "my_ip_cidr" {
  type = string
}

variable "key_name" {
  type    = string
  default = "wp-bootcamp-key"
}

variable "public_key_path" {
  type = string
}

variable "db_name" {
  type    = string
  default = "wordpress"
}

variable "db_user" {
  type    = string
  default = "wordpress"
}

variable "db_pass" {
  type      = string
  sensitive = true
}

variable "wp_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_desired" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 4
}
