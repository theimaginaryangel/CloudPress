# Security Groups
resource "aws_security_group" "alb" {
  name        = "cloudpress-alb-sg-${var.site_id}"
  description = "ALB security group for ${var.site_id}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloudpress-alb-sg-${var.site_id}"
    Site = var.site_id
  }
}

resource "aws_security_group" "ec2" {
  name        = "cloudpress-ec2-sg-${var.site_id}"
  description = "EC2 security group for ${var.site_id}"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow SSH from SSM / EC2 Instance Connect if needed later, but keeping it tight for now.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloudpress-ec2-sg-${var.site_id}"
    Site = var.site_id
  }
}

resource "aws_security_group" "rds" {
  name        = "cloudpress-rds-sg-${var.site_id}"
  description = "RDS security group for ${var.site_id}"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloudpress-rds-sg-${var.site_id}"
    Site = var.site_id
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "cloudpress-ec2-role-${var.site_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Site = var.site_id
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cloudpress-ec2-profile-${var.site_id}"
  role = aws_iam_role.ec2_role.name
}

# IAM Policy for Secrets Manager
resource "aws_iam_policy" "secrets_policy" {
  name        = "cloudpress-secrets-policy-${var.site_id}"
  description = "Allow EC2 to read RDS credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

# SSM Managed Instance Core (For Session Manager instead of SSH)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
