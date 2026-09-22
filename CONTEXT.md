# CloudPress - Build Context

Last updated: 2026-09-22T22:15:00Z by Antigravity (Gemini 3.1 Pro)

## Where this stands right now
Phase 5 is complete. We have successfully built the continuous monitoring system, resolved the CodeBuild tagging permission issues, cleaned up orphaned VPCs (resolving the VPC Limit Exceeded error), and completely verified an end-to-end provisioning of `test-site-api-12` and its health metrics generation. Phase 6 (Control Center Frontend) is ready to begin.

## Completed
- Phase 0.5 - The Context File: Initialized /CONTEXT.md and saved the master prompt.
- Phase 1 - Terraform: Single-Site Infrastructure Module: Done, verified.
- Phase 2 - Ansible: WordPress Provisioning Playbook: Done. Created /ansible roles (hardening, wordpress).
- Phase 3 - Deployment Orchestration API: Done. Built the API Gateway and Lambda orchestration layer.
- Phase 4 - Site Action Endpoints: Done. Built the site action endpoints.
- Phase 5 - Continuous Monitoring: Done, verified. Wrote `monitor.py` which runs via EventBridge, invokes SSM Run Command for WP-CLI metrics, checks CloudWatch for CloudFront 5xx errors, and updates DynamoDB.

## In progress
- Phase 6 - Control Center Frontend: Ready to start building the frontend dashboard.

## Not started
- Phase 6 - Control Center Frontend
- Phase 7 - Multi-Site Proof and Final Documentation Pass

## Decisions made this session (if any deviated from or extended Section 1)
- Added `cloudwatch:ListTagsForResource`, `cloudwatch:TagResource`, and `cloudwatch:UntagResource` to the CodeBuild orchestration IAM policy so Terraform can manage the tags of the CloudFront 5xx alarms.
- Enforced a hard cleanup of old `test-site-api-9`, `10`, and `11` VPCs, ENIs, ALBs, DB Subnet Groups, and RDS instances because CodeBuild could not destroy them due to `VpcLimitExceeded` blocking Terraform initialization/run.
- Used an empty `backend {}` config injection in CodeBuild via `backend.tf` to inject S3 configuration dynamically without polluting the local `main.tf` file.

## Known issues / blockers
- The WSL network on the host environment occasionally suffers from DNS drops or packet loss.

## Next action for the next agent
Read Phase 6 in MASTER_PROMPT.md. Build the Control Center Frontend.
