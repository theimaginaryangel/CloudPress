# Phase 1: Terraform Infrastructure Module

## What was built
We implemented a reusable Terraform module designed to provision the complete, isolated AWS infrastructure for a single WordPress site within the CloudPress ecosystem. 

The infrastructure provisioned includes:
* **Compute:** An EC2 instance (defaulting to `t3.micro`) acting as the underlying server for the WordPress application and its web server layer. This is placed behind an Application Load Balancer (ALB).
* **Database:** An RDS MySQL instance with a dedicated subnet group, ensuring that the database exists strictly in private subnets, completely inaccessible from the public internet. 
* **Secrets Management:** An AWS Secrets Manager secret is dynamically created to house the RDS credentials. The generated password is injected into the secret, meaning it is never exposed in plaintext files or logs.
* **Networking & Security:** We implemented strict security group rules. The ALB allows incoming HTTP/HTTPS traffic (port 80/443), the EC2 instance allows incoming traffic *only* from the ALB, and the RDS instance allows incoming traffic *only* from the EC2 instance. IAM roles strictly scope EC2 permissions, enabling SSM and Secrets Manager access without wildcards.
* **Storage:** We established IAM policies for the EC2 instance to interact strictly with its dedicated S3 prefix in a shared environment media bucket. 
* **Delivery:** A CloudFront CDN distribution sitting in front of the ALB for asset delivery, paired with a Route53 alias record mapping the provided custom domain.

## Why it was built this way
This phase strictly follows the locked architecture decisions defined in the master plan:
1. **Terraform-first:** Everything is codified in HCL to prevent manual operational steps, matching the mandate for 100% reproducible environments.
2. **One VPC / Segmented Security:** We structured the module to ingest shared VPC network IDs, preventing the unnecessary sprawl of VPCs per-site, while preserving isolation at the Security Group layer.
3. **No Wildcard Permissions:** The EC2 IAM role is tightly scoped to `secretsmanager:GetSecretValue` for its specific ARN, and S3 permissions apply solely to the site's unique prefix.
4. **RDS in Private Subnets:** The RDS instance's `publicly_accessible` flag is `false`, and its security group drops all traffic except the specific EC2 instance SG, fulfilling the security requirement.

## Operating and Extending
* **Applying the Module:** The module requires parameters like `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, and `route53_zone_id`. It does not provision its own VPC or Hosted Zone—these are assumed to be managed at the environment level (e.g., a central CloudPress networking state).
* **Instance Size Changes:** Vertical scaling can be achieved simply by updating the `instance_size` variable (e.g., from `t3.micro` to `t3.small`) and triggering a redeploy through the eventual API orchestrator.
* **SSM Access:** The EC2 role includes `AmazonSSMManagedInstanceCore`. Direct SSH is deliberately omitted from Security Groups. To access the instance, use AWS Systems Manager (Session Manager) rather than distributing key pairs.
