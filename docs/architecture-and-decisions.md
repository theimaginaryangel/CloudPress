# CloudPress: Architecture & Engineering Decisions
### Platform Engineering & Infrastructure Decisions for BennyDuah.com

---

## 1. Executive Summary

CloudPress is an enterprise-grade, API-driven WordPress hosting and control plane deployed entirely on Amazon Web Services (AWS). It combines modern Infrastructure-as-Code (Terraform), configuration management (Ansible), on-demand orchestration (AWS CodeBuild, API Gateway, and Lambda), continuous automated monitoring (EventBridge, SSM, and DynamoDB), and a brutalist, zero-slop Next.js dashboard into an isolated, multi-tenant capable architecture.

This document compiles the architectural principles, trade-offs, security invariants, and runtime decisions made across all seven development phases of CloudPress.

---

## 2. Core Architecture & Component Overview

```
                                  [ Client Browser ]
                                          |
                                          v
                       [ CloudPress Control Center (Next.js) ]
                                          |
                          (HTTPS REST / CORS Authenticated)
                                          v
                         [ AWS API Gateway (HTTP API v2) ]
                                          |
                                          v
                             [ API Lambda (Python 3.10) ]
                            +-------------+-------------+
                            |                           |
                            v                           v
                 [ Amazon DynamoDB ]           [ AWS CodeBuild ]
                (Sites & Telemetry)        (On-Demand Provisioning)
                                                |         |
                                                v         v
                                          [ Terraform ] [ Ansible ]
                                                |         |
                                                v         v
                        +----------------------------------------------+
                        |              Target Site VPC                 |
                        |                                              |
                        |   [ CloudFront CDN ] ---> [ ALB (Public) ]   |
                        |                                 |            |
                        |                                 v            |
                        |                     [ EC2 WordPress (App) ]  |
                        |                                 |            |
                        |                                 v            |
                        |                     [ RDS MySQL (Private) ]  |
                        +----------------------------------------------+
```

---

## 3. Phase-by-Phase Technical Ledger

### Phase 1: Infrastructure as Code (Terraform)
* **Single-Site Isolation**: Codified a modular, reusable AWS blueprint provisioning an Application Load Balancer, EC2 compute layer (`t3.micro`), and a private RDS MySQL instance.
* **Secrets Management**: Dynamically provisions AWS Secrets Manager secrets for database credentials. Passwords are generated securely in AWS and never exposed in plaintext code, shell variables, or version control.
* **Network Segmentation**: Strict security groups enforce zero direct internet access to database tiers. The RDS instance sits strictly in private subnets with `publicly_accessible = false`, accepting connections solely from the EC2 security group on port 3306.
* **IAM Least Privilege**: Replaced all potential wildcard permissions with scoped ARNs (`arn:aws:secretsmanager:*:secret:cloudpress-*` and instance profile roles).

### Phase 2: Configuration Management (Ansible over SSM)
* **Agentless, Keyless Provisioning**: Configured instances without opening inbound port 22 (SSH) and without distributing permanent private keys. Utilized the AWS Systems Manager (SSM) Session Manager tunnel (`amazon.aws.aws_ssm` plugin).
* **Production WordPress Stack**: Automated installation of Ubuntu 22.04 LTS, Nginx, PHP 8.1 FPM, and WordPress Core, along with WP-CLI for administrative automation.
* **Dynamic Salt & Config Generation**: Used Jinja2 templates (`wp-config.php.j2` and `nginx.conf.j2`) populated dynamically via JSON variables generated during the infrastructure build step.

### Phase 3: Deployment Orchestration (Serverless IaC Pipeline)
* **Serverless Build Plane**: Replaced expensive, long-running CI/CD instances and ECR containers with on-demand AWS CodeBuild containers (`aws/codebuild/standard:7.0`). CodeBuild runs only during provisioning or destruction, reducing idle platform overhead to $0.
* **REST API Layer**: API Gateway v2 routes requests to an orchestration Lambda (`cloudpress-api`), which records site state in DynamoDB (`cloudpress-sites`) and triggers CodeBuild asynchronously via `boto3`.
* **Isolated State Backends**: Configured remote S3 state storage partitioned per site ID (`$SITE_ID/terraform.tfstate`), ensuring that destroying or upgrading one site cannot corrupt the state of another.

### Phase 4: Lifecycle Operations & Day-2 Actions
* **Reboot Instance (`POST /sites/{site_id}/reboot`)**: Synchronously locates the site's tagged EC2 instance and triggers `ec2.reboot_instances` with immediate execution acknowledgement.
* **Live System Logs (`GET /sites/{site_id}/logs`)**: Uses SSM Run Command (`AWS-RunShellScript`) to fetch the last 100 lines of `/var/log/nginx/access.log` from the instance and streams them back through API Gateway.
* **Instant Backups (`POST /sites/{site_id}/backup`)**: Triggers an AWS EBS AMI snapshot (`ec2.create_image`) without requiring server reboots, paired simultaneously with an Amazon RDS manual database snapshot (`rds.create_db_snapshot`).

### Phase 5: Continuous Monitoring & Telemetry
* **Automated Hourly Audits**: EventBridge scheduled cron rule (`rate(1 hour)`) triggers `cloudpress-monitor` Lambda across all `AVAILABLE` sites.
* **In-Depth WP-CLI Introspection**: Rather than checking only HTTP ping availability, SSM Run Command queries the live WordPress runtime inside the instance using `sudo -u www-data`:
  * Core and Plugin updates counts (`wp core check-update`, `wp plugin list --update=available`).
  * Real-time disk utilization (`df -h`).
  * Active Administrator account audit (`wp user list --role=administrator`).
* **Active CloudWatch Alarms**: CloudFront `5xxErrorRate` threshold alarms (>5% over 5 minutes) configured per site.

### Phase 6: Next.js Control Center Dashboard
* **Brutalist, Zero-Slop Aesthetic**: Designed specifically to match the personal aesthetic of BennyDuah.com and Anchor.BennyDuah.com. Replaced standard SaaS generic templates with deep `#0a0a0a` dark mode, zinc color hierarchy, monospace typography (JetBrains Mono), and terminal-style metrics tables.
* **Non-Technical Management**: Complete deployment, live status polling, backup triggers, instance reboot, and teardown operable entirely through browser UI.
* **API Reliability**: Added HTTP API Gateway CORS headers and implemented a custom Python `DecimalEncoder` in the API Lambda to seamlessly serialize DynamoDB numeric values.

### Phase 7: Multi-Site Proof & Total Isolation Verification
* **Simultaneous Deployments**: Concurrently provisioned and operated multiple live sites (`site-kaluna`, `site-bennyduah`, and `test-site-api-12`).
* **Runtime Isolation Proof**: Verified that executing operational reboots on `site-kaluna` caused zero disruption or latency impact on `test-site-api-12`, proving complete VPC, compute, and database isolation.

---

## 4. Architectural Non-Negotiables & Invariants

1. **Zero Wildcard IAM**: All IAM roles (CodeBuild, Lambda, EC2 instance profiles) are bound to explicit resource ARNs and specific prefixes.
2. **Private Network Boundaries**: Database instances have no public IP addresses and cannot route to or from the public internet.
3. **No Hardcoded Secrets**: DB passwords, API tokens, and salts are generated dynamically inside AWS KMS/Secrets Manager.
4. **100% Codified Reproducibility**: From zero to a production-hardened WordPress deployment requires no manual console clicks or configuration tweaks.

---

*Compiled and verified for bennyduah.com.*
