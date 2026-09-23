# CloudPress — Master Execution Prompt

**Purpose of this document**: This is a portable, phase-based build prompt for an AI coding agent (Antigravity, OpenCode, Devin, Claude Code, or any other autonomous coding tool). This document defines the plan. A separate, living file — `CONTEXT.md`, described in Section 0.5 — carries the actual state of the build and must be created before Phase 1 begins. Any agent picking this up mid-build must read `CONTEXT.md` first, not this document's ledger alone, then resume at the first incomplete phase. Do not skip ahead. Do not improvise architecture decisions that are already locked in Section 1 — follow them exactly, even across a change of driving model.

---

## 0. Project Definition

CloudPress is a production-grade, API-driven WordPress hosting platform on AWS, paired with CloudPress Control Center, a dashboard that monitors and operates the sites CloudPress deploys.

This is not a demo. The finished system must be genuinely usable by a real client or agency, not just runnable by its author. That means:

- Deployment happens through an API call, not a human running console steps or scripts.
- Monitoring is live and continuous, not a one-time audit.
- Control Center can take real action on a site (restart, backup, deploy update, rollback), not just display metrics.
- The system is designed from the start to manage multiple independent WordPress sites, even though early phases prove the flow on one site before scaling out.

If any phase of this build produces something that only works when run manually by the developer, that phase is not complete. Re-do it as an API-triggered, agent-operable flow before moving on.

---

## 0.5 The Context File — Required Before Any Code Is Written

Before Phase 1 begins, create `/CONTEXT.md` at the repo root. This is the single file every agent — regardless of tool or model — reads first, every session, before touching code. It is the project's working memory across handoffs. Treat it as more authoritative than this document for "what state is the build actually in," because this document does not change and `CONTEXT.md` does.

`CONTEXT.md` must be updated at the end of every work session, not only at the end of a phase — if an agent stops mid-phase, the next agent (or the next session of the same agent) must be able to resume from exactly where work stopped, not from the start of the phase.

Required structure for `CONTEXT.md`:

```
# CloudPress — Build Context

Last updated: [date/time] by [agent/model name]

## Where this stands right now
One paragraph, plain language: what exists and runs today, what does not yet exist.

## Completed
- [Phase N — task]: done, verified [date]. [One line on what was actually confirmed working.]

## In progress
- [Phase N — task]: [specific sub-step reached, what's half-done, exact next action]

## Not started
- [Phase N — task]

## Decisions made this session (if any deviated from or extended Section 1)
- [Decision]: [why], [what it affects downstream]

## Known issues / blockers
- [Anything broken, any workaround used that should be revisited, any open question for the project owner]

## Next action for the next agent
One specific, concrete instruction — not "continue Phase 3" but "Phase 3: the /sites Lambda is written and deploys Terraform correctly; Ansible invocation is not yet wired in — pick up at connecting the Terraform output (instance IP) to the Ansible playbook run."
```

This file replaces vague resumption ("where were we") with an exact handoff. An agent that finishes a session without updating `CONTEXT.md` has not finished the session.

---

## 1. Locked Architecture Decisions

Do not deviate from these without the project owner's explicit sign-off. If a later phase seems to require deviating, stop and flag it rather than silently changing course.

**Infrastructure provisioning**: Terraform. Not CloudFormation, not CDK, not manual console steps in the final artifact (manual console use is permitted only for the developer's own one-time learning pass, never as part of the shipped system).

**Server configuration**: Ansible, run against EC2 instances after Terraform provisions them. Terraform provisions; Ansible configures. Do not blend the two — no provisioning logic inside Ansible playbooks, no OS-level configuration inside Terraform.

**Compute**: EC2 instances per WordPress site (not containers/ECS for v1 — keep this simple and debuggable; containerization is an explicit future phase, not part of this build).

**Database**: RDS MySQL, one DB subnet group spanning two Availability Zones minimum, instance not publicly accessible, reachable only from site EC2 security groups.

**Secrets**: AWS Secrets Manager for all DB credentials and any API keys. Nothing hardcoded, nothing in plaintext config files, nothing in environment variables checked into version control.

**Object storage**: S3 for WordPress media uploads, one bucket per environment (not per site, to avoid bucket sprawl — use prefixes to separate sites within the bucket).

**Networking**: One VPC. Public subnets for EC2 (behind an ALB), private subnets for RDS, spanning at least two AZs. Security groups scoped tightly — no `0.0.0.0/0` inbound except 80/443 on the ALB.

**IAM**: Every role scoped to only the actions and resource ARNs it needs. No wildcard resources (`"Resource": "*"`) anywhere in the system. No wildcard actions (`iam:*`, `ec2:*`, `s3:*` without a resource constraint) anywhere.

**Deployment API**: A small orchestration service (API Gateway + Lambda is the default choice — use a different compute target only if Lambda's execution time limit genuinely blocks a long-running Terraform/Ansible run, in which case use an ECS Fargate task triggered by the same API Gateway route) exposing at minimum:
- `POST /sites` — deploy a new WordPress site (body: site name, domain, plugin list)
- `GET /sites` — list all deployed sites and their status
- `GET /sites/{id}` — get one site's detail and health
- `POST /sites/{id}/restart` — restart a site's instance
- `POST /sites/{id}/backup` — trigger an on-demand backup
- `DELETE /sites/{id}` — tear down a site's infrastructure

**Data model**: Every resource created for a site (EC2 instance ID, RDS identifier if per-site, S3 prefix, DNS record) must be tracked against a `site_id` in a persistent store (DynamoDB is appropriate here — this is Control Center's own operational data, not WordPress's data, so DynamoDB's access pattern fits). Do not hardcode assumptions anywhere that only one site exists.

**Monitoring**: CloudWatch metrics and alarms per site, plus a scheduled Lambda (EventBridge-triggered, similar pattern to the BankGuard Compliance Auditor) that continuously checks each live site for: outdated WordPress core/plugins, SSL certificate expiry, disk usage thresholds, and unexpected admin-account changes. Findings get written to the same DynamoDB store and surfaced in Control Center.

**Frontend (Control Center)**: Next.js + Tailwind, matching the stack pattern already used across other completed projects (BankGuard, Kaluna) for consistency.

**CDN/DNS**: CloudFront in front of each site, Route 53 for subdomain management, provisioned by the same Terraform run that provisions the site's compute and storage.

---

## 2. Build Phases

Each phase must end in a working, verifiable state before the next begins. An agent must run the "Verification" step of a phase and confirm it passes before marking the phase complete.

**Every phase, without exception, requires three things before it counts as done — this is not optional for any phase, including small ones:**

1. **Run the phase's Verification step** and record the actual result (command output, screenshot description, response body), not just "passed."
2. **Run a security/quality audit against Section 1 and Section 3** before closing the phase: check for wildcard IAM, plaintext secrets, public RDS access, missing input validation on any new endpoint, and any manual step that snuck into the "shipped" path. Write findings directly into `CONTEXT.md` under "Known issues / blockers" if anything fails the audit — do not silently fix and forget, and do not close the phase with a known audit failure unresolved.
3. **Write the phase's documentation as part of the phase, not after.** Each phase gets a short doc file under `/docs/` (e.g. `/docs/phase-1-infrastructure.md`) written in professional, plain-English prose: what was built, why it was built that way (tie back to the Section 1 decision it implements), and what a reader would need to know to operate or extend it. This is not a code comment substitute — it is the material that becomes the bennyduah.com write-up later, so it must read as finished documentation, not build notes.

A phase is not complete until `CONTEXT.md` is updated, the audit has been run and any findings resolved or explicitly logged, and that phase's doc file exists.

### Phase 1 — Terraform: Single-Site Infrastructure Module
Write a reusable Terraform module that provisions one WordPress site's infrastructure: VPC (if not already shared), public/private subnets across 2 AZs, EC2 instance, RDS MySQL instance, security groups, IAM role scoped per Section 1, Secrets Manager secret, S3 prefix, CloudFront distribution, Route 53 record. Module must accept `site_id`, `domain`, and `instance_size` as variables — no hardcoded single-site assumptions.
**Verification**: `terraform apply` with a test `site_id` produces a reachable EC2 instance and a private, unreachable-from-internet RDS instance. Confirm via `curl` (should fail/timeout) that RDS port 3306 is not reachable from outside the VPC.

### Phase 2 — Ansible: WordPress Provisioning Playbook
Write an Ansible playbook that installs and configures WordPress, PHP, and Nginx/Apache on a freshly Terraform-provisioned EC2 instance. Playbook must fetch the DB password from Secrets Manager at runtime (via the instance's IAM role), not receive it as a plaintext variable. Include OS hardening tasks: disable root SSH login, configure `fail2ban`, enable unattended security updates.
**Verification**: Running the playbook against a Phase 1 instance results in a live WordPress install reachable over HTTP(S), with `wp-config.php` containing no plaintext password.

### Phase 3 — Deployment Orchestration API
Build the `POST /sites` Lambda (or Fargate task) that, given a site name and domain, runs Terraform (Phase 1 module) then Ansible (Phase 2 playbook) against the new instance, and records the result in DynamoDB. Include the `GET /sites` and `GET /sites/{id}` read endpoints.
**Verification**: A single API call to `POST /sites` with a new site name results in a live, reachable WordPress site with no manual steps, and `GET /sites` reflects it.

### Phase 4 — Site Action Endpoints
Build `POST /sites/{id}/restart`, `POST /sites/{id}/backup`, and `DELETE /sites/{id}`. Restart should act on the actual EC2 instance (not just report success). Backup should produce a real, restorable RDS snapshot plus an S3 copy of the media prefix. Delete should tear down all Terraform-managed resources for that site and remove its DynamoDB record.
**Verification**: Each endpoint produces a verifiable real-world effect — restart causes a brief downtime and recovery, backup produces a snapshot visible in the RDS console/API, delete leaves no orphaned AWS resources (confirm via a resource audit script).

### Phase 5 — Continuous Monitoring
Build the EventBridge-scheduled Lambda that checks every live site (via the DynamoDB site registry) for outdated plugins/core, SSL expiry, disk usage, and unexpected admin changes. Write findings to DynamoDB. Wire CloudWatch alarms for basic uptime/error-rate per site.
**Verification**: Deliberately let a test site's WordPress fall out of date or let a self-signed cert near expiry; confirm the scheduled check flags it within one run cycle.

### Phase 6 — Control Center Frontend
Build the Next.js dashboard: site list with live status, per-site detail view showing CloudWatch metrics and monitoring findings from Phase 5, and buttons wired to the Phase 3/4 API endpoints (deploy, restart, backup, delete).
**Verification**: A non-technical user can deploy a new site, watch its status go live, and trigger a restart or backup, entirely through the UI with no terminal access.

### Phase 7 — Multi-Site Proof and Final Documentation Pass
Deploy at least two sites simultaneously through the system, confirm total isolation between them (one site's failure/restart does not affect the other), and confirm Control Center correctly lists and operates both independently. Assemble the per-phase doc files from `/docs/` into one coherent architecture and decisions document for bennyduah.com — this is a compilation and edit pass, not a from-scratch write, since each phase already documented itself as it went.
**Verification**: Two live, independent sites, both operable from Control Center, plus one complete, readable decisions document assembled from the phase docs.

---

## 3. Non-Negotiable Constraints (apply at every phase)

- No wildcard IAM permissions, ever, for any convenience reason.
- No plaintext secrets in code, config files, or environment variables committed to version control.
- No manual, undocumented steps in the final system — everything a phase produces must be reproducible by another agent from the code alone.
- Every phase's verification step must be actually run and its result recorded in the Build State Ledger, not assumed.
- If a phase cannot be completed as specified, stop and document exactly why in the ledger rather than silently substituting an easier approach.

---

## 4. Build State Ledger

This table is a quick-reference index only. `CONTEXT.md` (Section 0.5) is the authoritative, detailed state and must be kept current every session — update this table whenever `CONTEXT.md` changes so the two never drift out of sync.

| Phase | Status | Audit run? | Doc file exists? |
|---|---|---|---|
| 1 — Terraform single-site module | Complete | Yes | Yes (`docs/phase-1-infrastructure.md`) |
| 2 — Ansible WordPress playbook | Complete | Yes | Yes (`docs/phase-2-ansible.md`) |
| 3 — Deployment orchestration API | Complete | Yes | Yes (`docs/phase-3-orchestration.md`) |
| 4 — Site action endpoints | Complete | Yes | Yes (`docs/phase-4-actions.md`) |
| 5 — Continuous monitoring | Complete | Yes | Yes (`docs/phase-5-monitoring.md`) |
| 6 — Control Center frontend | Complete | Yes | Yes (`docs/phase-6-frontend.md`) |
| 7 — Multi-site proof + final docs | Complete | Yes | Yes (`docs/architecture-and-decisions.md`) |
