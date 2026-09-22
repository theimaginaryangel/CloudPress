# Phase 4: Site Action Endpoints

## Overview
Phase 4 extends the core orchestration API to support ongoing lifecycle actions for deployed CloudPress sites. It adds endpoints to reboot, fetch logs, trigger backups, and destroy the infrastructure.

## Architecture & Implementation
The operations are handled synchronously or asynchronously depending on their complexity:

### 1. Delete (`DELETE /sites/{site_id}`)
- **Operation**: Asynchronous via CodeBuild
- **Implementation**: The Lambda sets the DynamoDB state to `DESTROYING` and triggers CodeBuild with `ACTION="DESTROY"`.
- **CodeBuild**: Executes `terraform destroy -auto-approve` and deletes the DynamoDB item upon success.

### 2. Reboot (`POST /sites/{site_id}/reboot`)
- **Operation**: Synchronous via boto3
- **Implementation**: The Lambda queries EC2 instances by the tag `Name = cloudpress-ec2-{site_id}` and triggers `ec2.reboot_instances()`.

### 3. Logs (`GET /sites/{site_id}/logs`)
- **Operation**: Synchronous via AWS SSM
- **Implementation**: The Lambda finds the instance ID, sends a shell command (`tail -n 100 /var/log/nginx/access.log`) using `ssm:SendCommand`, polls briefly for completion, and fetches the log output using `ssm:GetCommandInvocation`.

### 4. Backup (`POST /sites/{site_id}/backup`)
- **Operation**: Synchronous invocation (Async backup process)
- **Implementation**: 
  - **EC2**: Calls `ec2.create_image(NoReboot=True)` to create an AMI of the web server.
  - **RDS**: Calls `rds.create_db_snapshot()` to create a manual database snapshot.
  - Both operations return the generated snapshot and AMI IDs immediately.

## Security Updates
The IAM Role attached to the API Lambda was expanded to include strictly scoped `ec2:RebootInstances`, `ec2:CreateImage`, `rds:CreateDBSnapshot`, and `ssm:SendCommand` actions.
