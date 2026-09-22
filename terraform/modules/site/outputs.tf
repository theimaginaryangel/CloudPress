output "ec2_instance_id" {
  description = "ID of the WordPress EC2 instance"
  value       = aws_instance.wordpress_ec2.id
}

output "ec2_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.wordpress_ec2.public_ip
}

output "ec2_private_key" {
  description = "The SSH private key for the EC2 instance"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
