resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "cloudpress/db/${var.site_id}"
  description = "RDS MySQL credentials for ${var.site_id}"

  tags = {
    Site = var.site_id
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "wp_admin"
    password = random_password.db_password.result
  })
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "cloudpress-db-subnet-group-${var.site_id}"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "cloudpress-db-subnet-group-${var.site_id}"
    Site = var.site_id
  }
}

resource "aws_db_instance" "wordpress_db" {
  identifier        = "cloudpress-db-${var.site_id}"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = "wordpress"
  username = "wp_admin"
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true # For development; change to false for production

  backup_retention_period = 7

  tags = {
    Name = "cloudpress-db-${var.site_id}"
    Site = var.site_id
  }
}
