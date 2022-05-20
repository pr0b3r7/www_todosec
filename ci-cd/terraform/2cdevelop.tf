# VARS block
variable "ssh_port" {
  description = "The port the server will use for sshd"
  type = number
  default = 22
}
variable "http_port" {
  description = "The port the server will use for http"
  type = number
  default = 8090
}
variable "all_inet" {
  description = "All Internet networks"
  type = list
  default = ["0.0.0.0/0"]
}

### end VARS block

provider "aws" {}

// Create new EC2 Instance
#resource "aws_instance" "wp-01" {
resource "aws_launch_configuration" "wp-01" {
#  ami = "ami-09d56f8956ab235b3"
  image_id = "ami-09d56f8956ab235b3"
  instance_type = "t3.micro"
  key_name= "aws_key"
  associate_public_ip_address = true
#    security_groups = ["${aws_security_group.ingress-ssh-wp.id}"]
#  vpc_security_group_ids = [aws_security_group.ingress-ssh-wp.id] 
  security_groups = [aws_security_group.ingress-ssh-wp.id] 
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World ($HOSTNAME)" > index.html 
    nohup busybox httpd -f -p ${var.http_port} &
    EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wp-01" {
    launch_configuration = aws_launch_configuration.wp-01.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"
    min_size = 1
    max_size = 2
    tag { 
        key = "Name"
        value = "terraform-asg-wp-01"
        propagate_at_launch = true
    }
}


## add ALB
resource "aws_lb" "wp-alb-01" {
  name               = "terraform-asg-wp-01"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "asg" {
     name     = "terraform-asg-wp-01"
     port     = var.http_port
     protocol = "HTTP"
     vpc_id   = data.aws_vpc.default.id
  health_check {
    path = "/"
    protocol = "HTTP" 
    matcher = "200"
    interval = 15
    timeout =3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
     listener_arn = aws_lb_listener.http.arn
     priority = 100
    condition {
      path_pattern {
        values = ["*"]
      }
    }
     action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    } 
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_vpc" "default" {
     default = true
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wp-alb-01.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-wp-01-alb"
    ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = var.all_inet
    }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = var.all_inet
  } 
}

## add ssh key
resource "aws_key_pair" "deployer" {
  key_name   = "aws_key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKV6AdnahiZUew7L9D0Idvt/uTMd+VuNHPUwnzbHowbt sws@mbpsws.local"
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

// Add ssh allow rule 
resource "aws_security_group" "ingress-ssh-wp" {
name = "ingress-ssh-wp"
#vpc_id = "aws_default_vpc.default.id"
ingress {
    cidr_blocks = var.all_inet
    from_port = var.ssh_port
    to_port = var.ssh_port
    protocol = "tcp"
}
ingress {
    cidr_blocks = var.all_inet
    from_port = var.http_port
    to_port = var.http_port
    protocol = "tcp"
}
}

// output Elastic IP for ALB balancer
output "alb_dns_name" {
  value       = aws_lb.wp-alb-01.dns_name
  description = "The domain name of the load balancer"
}