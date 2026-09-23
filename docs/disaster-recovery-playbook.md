# CloudPress Enterprise Disaster Recovery (DR) Playbook

## 1. Executive Summary & Recovery Objectives

For agencies and enterprises deploying mission-critical WordPress sites on AWS, data safety, uptime guarantees, and disaster recoverability are foundational requirements. 

This playbook outlines CloudPress's disaster recovery architecture, automated backup lifecycle, and step-by-step restoration procedures for failure scenarios.

### Target Recovery Metrics

| Metric | Target | Rationale |
| :--- | :--- | :--- |
| **Recovery Point Objective (RPO)** | **< 24 Hours** (Automated Daily) / **< 5 Minutes** (On-Demand / Pre-Update) | Daily automated snapshots run every 24 hours. Additionally, atomic pre-update snapshots execute before any core/plugin upgrade. |
| **Recovery Time Objective (RTO)** | **< 15 Minutes** | Automated AMI and RDS snapshot restoration enables rapid instance provisioning without rebuilding OS or re-importing multi-gigabyte SQL dumps manually. |

---

## 2. Backup Architecture & Lifecycle

CloudPress provides two distinct layers of backup automation:

```
+-----------------------------------------------------------------------------------+
|                            CloudPress Backup Engine                               |
+-----------------------------------------------------------------------------------+
                               |
        +----------------------+----------------------+
        |                                             |
        v                                             v
+-------------------------------+             +-------------------------------+
|       EC2 AMI Snapshots       |             |         RDS Snapshots         |
|  - Full root filesystem (/dev)|             |  - Full MySQL/MariaDB storage |
|  - Nginx, PHP, WP Core/Uploads|             |  - Consistent InnoDB state    |
|  - Tag: cloudpress-backup-*   |             |  - Tag: cloudpress-db-backup-*|
+-------------------------------+             +-------------------------------+
        |                                             |
        +----------------------+----------------------+
                               |
                               v
+-----------------------------------------------------------------------------------+
|                        Automated 7-Day Rolling Retention                          |
|   Hourly monitor sweeps deregister AMIs & delete EBS/RDS snapshots > 7 days old   |
+-----------------------------------------------------------------------------------+
```

1. **Daily Automated Snapshots**:
   - The `cloudpress-monitor` Lambda function runs hourly via EventBridge.
   - For every site in `AVAILABLE` status with `last_backup_time` older than 24 hours (or not yet recorded), it triggers an atomic snapshot pair:
     - EC2 AMI: `cloudpress-backup-{site_id}-{timestamp}`
     - RDS DB Snapshot: `cloudpress-db-backup-{site_id}-{timestamp}`
   - Enforces a **7-day rolling retention policy**: deregisters AMIs older than 7 days, removes dangling EBS snapshots, and deletes expired RDS manual snapshots.

2. **On-Demand & Pre-Update Safety Snapshots**:
   - Triggered either manually via dashboard (`POST /sites/{site_id}/backup`) or automatically before core/plugin updates (`POST /sites/{site_id}/update`).
   - Guarantees immediate rollback points before applying updates to production.

---

## 3. Incident Response & Restoration Playbooks

### Scenario A: Broken WordPress Update (Corrupted Code or Incompatible Plugin)

**Symptoms**: HTTP 500 error, White Screen of Death (WSOD), or database schema migration errors immediately following an update.

#### Step 1: Diagnose using CloudPress SSM
Run WordPress verification commands via AWS Systems Manager without SSH:
```bash
aws ssm send-command \
  --instance-ids "<INSTANCE_ID>" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u www-data wp core verify-checksums --path=/var/www/<DOMAIN>","sudo -u www-data wp plugin list --status=active --path=/var/www/<DOMAIN>"]' \
  --region us-east-1
```

#### Step 2: Immediate Plugin Rollback or Deactivation
If a specific plugin caused the crash:
```bash
aws ssm send-command \
  --instance-ids "<INSTANCE_ID>" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u www-data wp plugin deactivate <BAD_PLUGIN_SLUG> --path=/var/www/<DOMAIN>"]' \
  --region us-east-1
```

#### Step 3: Full Code Rollback from Pre-Update AMI
If the filesystem was damaged, launch a replacement EC2 instance from the pre-update AMI (`cloudpress-backup-{site_id}-{timestamp}`) and swap it into the Application Load Balancer target group.

---

### Scenario B: Database Corruption or Accidental Table Deletion

**Symptoms**: "Error establishing a database connection" or lost WooCommerce orders / user tables.

#### Step 1: Identify Latest Healthy DB Snapshot
List available snapshots for the target site:
```bash
aws rds describe-db-snapshots \
  --db-instance-identifier "cloudpress-db-<SITE_ID>" \
  --query "DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]" \
  --output table \
  --region us-east-1
```

#### Step 2: Restore DB Snapshot to Temporary Instance
Restore the snapshot to a new instance name (RDS requires new instance identifier):
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "cloudpress-db-<SITE_ID>-restored" \
  --db-snapshot-identifier "<SNAPSHOT_IDENTIFIER>" \
  --db-instance-class db.t4g.micro \
  --vpc-security-group-ids "<DB_SECURITY_GROUP_ID>" \
  --region us-east-1
```

#### Step 3: Verify and Point WordPress to Restored Database
Once the status changes to `available`:
1. Retrieve the restored database endpoint:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier "cloudpress-db-<SITE_ID>-restored" \
     --query "DBInstances[0].Endpoint.Address" \
     --output text \
     --region us-east-1
   ```
2. Update the `DB_HOST` in `/var/www/<DOMAIN>/wp-config.php` via SSM:
   ```bash
   aws ssm send-command \
     --instance-ids "<INSTANCE_ID>" \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["sudo -u www-data wp config set DB_HOST <RESTORED_ENDPOINT> --path=/var/www/<DOMAIN>"]' \
     --region us-east-1
   ```
3. Once verified, delete the old corrupted RDS instance:
   ```bash
   aws rds delete-db-instance \
     --db-instance-identifier "cloudpress-db-<SITE_ID>" \
     --skip-final-snapshot \
     --region us-east-1
   ```

---

### Scenario C: EC2 Hardware Failure or Underlying Host Degradation

**Symptoms**: AWS health check alarm, instance unreachable, or EC2 host retirement notice.

#### Step 1: Find the Latest Golden AMI
```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=cloudpress-backup-<SITE_ID>-*" \
  --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" \
  --output text \
  --region us-east-1
```

#### Step 2: Launch Replacement Instance
Launch an EC2 instance with identical IAM instance profile (`cloudpress-ec2-role`) and VPC subnet:
```bash
aws ec2 run-instances \
  --image-id "<LATEST_AMI_ID>" \
  --instance-type t3.micro \
  --iam-instance-profile Name="cloudpress-ec2-role" \
  --security-group-ids "<APP_SECURITY_GROUP_ID>" \
  --subnet-id "<PRIVATE_OR_PUBLIC_SUBNET_ID>" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=cloudpress-ec2-<SITE_ID>},{Key=SiteId,Value=<SITE_ID>}]" \
  --region us-east-1
```

#### Step 3: Register New Instance with Target Group
Register the new instance ID with the site's Application Load Balancer Target Group:
```bash
# Register target
aws elbv2 register-targets \
  --target-group-arn "<TARGET_GROUP_ARN>" \
  --targets Id="<NEW_INSTANCE_ID>" \
  --region us-east-1

# Deregister degraded target
aws elbv2 deregister-targets \
  --target-group-arn "<TARGET_GROUP_ARN>" \
  --targets Id="<OLD_INSTANCE_ID>" \
  --region us-east-1
```
The ALB health check (`/`) will mark the new instance healthy within 30 seconds, restoring 100% traffic without downtime.

---

## 4. Disaster Recovery Testing & Validation Drill (Quarterly Protocol)

To comply with enterprise SLAs, agencies should run a simulated recovery drill every 90 days:
1. **Trigger Manual Snapshot**: Send `POST /sites/{site_id}/backup`.
2. **Spin Up Staging Replica**: Restore the snapshot to a sandbox subnet.
3. **Run WP Smoke Test**: Send HTTP requests to `/wp-json/wp/v2/posts` on the restored endpoint.
4. **Sign Off & Tear Down**: Log RTO elapsed time in agency audit records and terminate drill resources.
