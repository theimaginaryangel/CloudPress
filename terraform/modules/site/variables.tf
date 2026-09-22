variable "site_id" {
  description = "Unique identifier for the WordPress site"
  type        = string
}

variable "domain" {
  description = "Domain name for the site"
  type        = string
}

variable "instance_size" {
  description = "EC2 instance type for the WordPress compute"
  type        = string
  default     = "t3.micro"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "environment" {
  description = "Environment name (e.g., prod, dev)"
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "ID of the shared VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (at least 2)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (at least 2)"
  type        = list(string)
}

variable "media_bucket_name" {
  description = "Name of the shared S3 bucket for media"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 Hosted Zone ID for the domain"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the CloudFront distribution. If empty, the default CloudFront cert is used and the custom domain alias is skipped (useful for dev/testing)."
  type        = string
  default     = ""
}
