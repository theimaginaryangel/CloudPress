data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "cloudpress-key-${var.site_id}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "aws_instance" "wordpress_ec2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_size
  subnet_id     = var.public_subnet_ids[0]

  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_key.key_name

  tags = {
    Name = "cloudpress-ec2-${var.site_id}"
    Site = var.site_id
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "cloudpress-alb-${var.site_id}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "cloudpress-alb-${var.site_id}"
    Site = var.site_id
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "cloudpress-tg-${var.site_id}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "wordpress_ec2_attach" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_ec2.id
  port             = 80
}
