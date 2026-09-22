provider "aws" {
  region = "us-east-1"
}

# Create a basic VPC for the test environment
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "cloudpress-dev-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "dev"
  }
}

# Dummy Route53 zone for testing (will create a private one to avoid needing domain registration for the test)
resource "aws_route53_zone" "test_zone" {
  name = "test.cloudpress.local"

  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

# S3 Media Bucket
resource "aws_s3_bucket" "media_bucket" {
  bucket_prefix = "cloudpress-media-dev-"
}

# Call the Site Module
module "wordpress_site" {
  source = "../../modules/site"

  site_id            = "test-site-03"
  domain             = "test-site-03.test.cloudpress.local"
  instance_size = "t3.micro"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  media_bucket_name = aws_s3_bucket.media_bucket.bucket
  route53_zone_id   = aws_route53_zone.test_zone.zone_id
}

output "ec2_public_ip" {
  value = module.wordpress_site.ec2_public_ip
}

output "ec2_private_key" {
  value     = module.wordpress_site.ec2_private_key
  sensitive = true
}

output "ec2_instance_id" {
  value = module.wordpress_site.ec2_instance_id
}

output "alb_dns_name" {
  value = module.wordpress_site.alb_dns_name
}

output "rds_endpoint" {
  value = module.wordpress_site.rds_endpoint
}
