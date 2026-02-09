terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  subnets_by_az = { for s in data.aws_subnet.default : s.availability_zone => s.id... }
  alb_subnets   = [for az, ids in local.subnets_by_az : ids[0]]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "wp" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_security_group" "alb_sg" {
  name   = "wp-alb-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wp_sg" {
  name   = "wp-ec2-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "wp-rds-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wp_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "jenkins_sg" {
  name   = "jenkins-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "wp-db-subnets"
  subnet_ids = local.alb_subnets
}

resource "aws_db_instance" "wp" {
  identifier             = "wp-bootcamp-db"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_pass
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name
}

resource "aws_lb" "wp" {
  name               = "wp-alb"
  load_balancer_type = "application"
  subnets            = local.alb_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "wp" {
  name     = "wp-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wp.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wp.arn
  }
}

locals {
  wp_user_data = base64encode(templatefile("${path.module}/user_data_wp.sh", {
    db_host = aws_db_instance.wp.address
    db_user = var.db_user
    db_pass = var.db_pass
    db_name = var.db_name
  }))
}

resource "aws_launch_template" "wp" {
  name_prefix   = "wp-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.wp_instance_type
  key_name      = aws_key_pair.wp.key_name

  user_data = local.wp_user_data

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wp-asg-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "wp-asg-node"
    }
  }

  network_interfaces {
    security_groups = [aws_security_group.wp_sg.id]
  }
}

resource "aws_autoscaling_group" "wp" {
  name                = "wp-asg"
  min_size            = var.asg_min
  desired_capacity    = var.asg_desired
  max_size            = var.asg_max
  vpc_zone_identifier = local.alb_subnets

  launch_template {
    id      = aws_launch_template.wp.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.wp.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 180
}

resource "aws_autoscaling_policy" "wp_cpu" {
  name                   = "wp-cpu-target-50"
  autoscaling_group_name = aws_autoscaling_group.wp.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0

    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.jenkins_instance_type
  key_name               = aws_key_pair.wp.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  subnet_id              = element(local.alb_subnets, 0)

  tags = { Name = "jenkins-ec2" }
}
