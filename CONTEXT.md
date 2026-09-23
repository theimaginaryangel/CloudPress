# CloudPress - Build Context

Last updated: 2026-09-23T08:35:00Z by Antigravity

## Where this stands right now
All phases (Phase 0.5 through Phase 7) are complete and verified. CloudPress is fully built, documented, and operational with live sites provisioned in AWS.

## Completed
- Phase 0.5 - The Context File: Initialized /CONTEXT.md and saved the master prompt.
- Phase 1 - Terraform: Single-Site Infrastructure Module: Done, verified. Modular single-tenant site topology with private RDS, CloudFront CDN, and Secrets Manager.
- Phase 2 - Ansible: WordPress Provisioning Playbook: Done, verified. Production-grade Nginx + PHP-FPM + WordPress setup over AWS Systems Manager (SSM) Session Manager.
- Phase 3 - Deployment Orchestration API: Done, verified. API Gateway v2 + Lambda + CodeBuild serverless runner with remote S3 state isolation.
- Phase 4 - Site Action Endpoints: Done, verified. Lifecycle actions implemented for reboot, live Nginx logs, and simultaneous EBS/RDS automated snapshots.
- Phase 5 - Continuous Monitoring: Done, verified. EventBridge scheduled Lambda executing WP-CLI introspection via SSM Run Command, CloudWatch 5xx alarm tracking, and DynamoDB health metrics.
- Phase 6 - Control Center Frontend: Done, verified. Next.js 16 dashboard with a bespoke brutalist dark mode (inspired by bennyduah.com and anchor.bennyduah.com), API Gateway CORS support, and DynamoDB Decimal serialization handling.
- Phase 7 - Multi-Site Proof and Final Documentation Pass: Done, verified. Demonstrated multi-site concurrent operation and fault isolation across independent VPCs (site-kaluna, site-bennyduah, test-site-api-12). Compiled complete, unified architecture and decisions document in `/docs/architecture-and-decisions.md`.

## In progress
- None. All phases complete.

## Not started
- None. All phases complete.

## Decisions made this project
- Used AWS Systems Manager (SSM) connection plugin for Ansible to eliminate permanent private keys and public SSH access.
- Selected AWS CodeBuild as a cost-effective, on-demand serverless IaC execution engine instead of maintaining persistent orchestration compute.
- Adopted strict per-site S3 state partitioning (`$SITE_ID/terraform.tfstate`) to isolate blast radiuses.
- Implemented a custom `DecimalEncoder` in the Python Lambda layer to safely serialize DynamoDB numeric attributes.
- Configured native API Gateway v2 CORS handling to support secure client-side browser communication from the Control Center frontend.
- Designed a brutalist, zero-slop dark aesthetic for the Control Center to maintain visual consistency with bennyduah.com and anchor.bennyduah.com.

## Known issues / blockers
- None.

## Next steps
- The platform is ready for production usage.
