# Phase 5: Continuous Monitoring

## Overview

Phase 5 introduces active, hourly health and security monitoring for all `AVAILABLE` WordPress sites managed by CloudPress. This is achieved using an AWS EventBridge scheduled rule, an AWS Lambda function (`cloudpress-monitor`), and AWS Systems Manager (SSM) Run Command. 

The monitor checks several key metrics and properties of each site and writes the results back to the `cloudpress-sites` DynamoDB table under the `health_metrics` map.

## Architecture

1. **EventBridge Rule**: Runs once per hour (`cron(0 * * * ? *)`), triggering the `cloudpress-monitor` Lambda function.
2. **Lambda Function (`cloudpress-monitor`)**:
   - Scans the `cloudpress-sites` DynamoDB table for sites with `status = AVAILABLE`.
   - Uses Python's `ssl` and `socket` libraries to fetch the SSL certificate for the site's domain and calculates the number of days until expiry (`ssl_days_remaining`).
   - Uses `boto3` to find the corresponding EC2 instance ID for each site (via the `tag:Site` filter).
   - Invokes `ssm:SendCommand` (using the `AWS-RunShellScript` document) to execute commands on the EC2 instance.
3. **SSM Run Command**:
   - Executes `df -h / | tail -1 | awk '{print $5}'` to get disk usage (`disk_usage`).
   - Executes `sudo -u www-data wp core check-update --path=/var/www/<domain> --format=json` to get pending WordPress core updates.
   - Executes `sudo -u www-data wp plugin list --update=available --format=json --path=/var/www/<domain>` to get pending plugin updates.
   - Executes `sudo -u www-data wp user list --role=administrator --format=json --path=/var/www/<domain>` to get a list of administrator users.
   - **Note**: The execution relies on WP-CLI, which was added to the Ansible provisioning script (`tasks/main.yml`) as part of this phase.
4. **DynamoDB Update**: 
   - The Lambda function parses the SSM Run Command output and calculates `core_updates` (count), `plugin_updates` (count), and `admins` (list of strings).
   - Updates the site's DynamoDB record with the new `health_metrics`.
5. **CloudWatch Alarms**:
   - CloudFront 5xx error alarms are provisioned for each site (`terraform/modules/site/dns_cdn.tf`). The alarm monitors the `5xxErrorRate` metric and triggers if it exceeds 5% over 5 minutes.

## Security Constraints Enforced

- **IAM Policies**: The `cloudpress-api-lambda-role` was explicitly updated to grant strictly scoped access:
  - `ssm:SendCommand` and `ssm:GetCommandInvocation` on `arn:aws:ec2:us-east-1:*:instance/*` and `arn:aws:ssm:us-east-1:*:document/AWS-RunShellScript`.
  - No wildcard `ssm:*` or `ec2:*` permissions were granted.
- **WP-CLI**: Commands are run with `sudo -u www-data` because SSM Run Command executes as root, but WP-CLI provides safe JSON output parsing to avoid shell injection or complex text parsing errors.

## Testing & Verification

1. Provisioned a test site (`test-site-api-9`) via the orchestrator API.
2. Verified the site reached `AVAILABLE` status.
3. Manually invoked the `cloudpress-monitor` Lambda function.
4. Verified that the `health_metrics` object in DynamoDB was populated with:
   - `ssl_days_remaining`
   - `disk_usage`
   - `core_updates`
   - `plugin_updates`
   - `admins`
5. Verified the CloudWatch Alarm for CloudFront 5xx errors was created successfully.

## Known Limitations & Future Work

- The SSL check performs a direct socket connection to the domain. If the domain is not resolving (e.g., DNS not configured by the client), the SSL check may fail or timeout. The code handles connection errors gracefully and skips the SSL metric update.
- The Lambda function uses a sequential loop to process sites. If the number of sites grows significantly (e.g., hundreds), the Lambda may hit the 15-minute timeout. Future enhancements should consider asynchronous invocation (e.g., SQS queue per site) or concurrent futures.
