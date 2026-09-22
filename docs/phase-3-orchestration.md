# Phase 3: Deployment Orchestration API

## Overview
Phase 3 implements the control plane and orchestration layer that links the API Gateway to our Terraform and Ansible infrastructure. It allows CloudPress to provision new WordPress sites dynamically via a simple REST API call.

## Architecture
To avoid the high costs of continuously running ECR containers or NAT Gateways for Lambda, we utilize AWS CodeBuild as an on-demand, serverless execution engine for our IaC.

- **API Gateway**: Provides the REST endpoint (`POST /sites`).
- **Lambda (`app.py`)**: Validates requests, writes initial state to DynamoDB, and triggers the CodeBuild project asynchronously using `boto3`.
- **DynamoDB (`cloudpress-sites`)**: Stores the state of each site (`PROVISIONING`, `AVAILABLE`, `FAILED`, etc.) and its metadata.
- **AWS CodeBuild**: The build runner that executes Terraform and Ansible in an isolated, temporary Ubuntu environment.
- **S3 Buckets**: 
  - `Source Bucket`: Stores the zipped CloudPress repository containing the Terraform modules and Ansible playbooks.
  - `State Bucket`: Stores the dynamic Terraform state files (`terraform.tfstate`) partitioned by `site_id`.

## The CodeBuild Pipeline (`buildspec.yml`)
The buildspec is the heart of the orchestrator. It performs the following phases:
1. **INSTALL**: Downloads and installs Terraform, Ansible, `boto3`, and the AWS Session Manager Plugin for Ubuntu.
2. **BUILD (Terraform)**:
   - Initializes the Terraform `dev` environment using the remote S3 backend, parameterized by `SITE_ID`.
   - Executes `terraform apply -auto-approve` to provision the AWS infrastructure.
   - Extracts the resulting IP, DB credentials, and endpoints into an `ansible_vars.json` file.
3. **POST_BUILD (Ansible)**:
   - Connects to the newly provisioned EC2 instance using the AWS SSM plugin (`ansible_connection=aws_ssm`).
   - Runs the `site.yml` Ansible playbook, passing in `ansible_vars.json` to configure WordPress.
   - Updates the site status in DynamoDB to `AVAILABLE` (if successful) or `FAILED` (if any step failed).

## IAM Security
The orchestration layer strictly adheres to least-privilege principles. The CodeBuild IAM Role is bounded to only operate on resources prefixed with `cloudpress-*` and explicitly blocks wildcards for sensitive actions.

## Usage
To provision a new site:
```bash
curl -X POST https://<API_ID>.execute-api.us-east-1.amazonaws.com/sites \
     -H "Content-Type: application/json" \
     -d '{"site_id": "my-site", "domain": "my-site.cloudpress.local"}'
```
