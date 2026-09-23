# Phase 6: Control Center Frontend

## Overview

Phase 6 provides a dedicated, non-technical dashboard for managing CloudPress sites called the **CloudPress Control Center**. The frontend is built using Next.js 16 (App Router), Tailwind CSS v4, and SWR for reactive telemetry and status polling.

The design departs deliberately from generic "SaaS UI slop", adopting a brutalist, minimal, monochromatic dark aesthetic inspired by the personal design language of `bennyduah.com` and `anchor.bennyduah.com` (deep `#0a0a0a` background, `zinc` accents, monospace tracking, and strict border-based layouts).

## Architecture & Features

### 1. Technology Stack
- **Framework**: Next.js 16 (App Router + Turbopack)
- **Styling**: Tailwind CSS v4 with custom `@theme` palette (`zinc-100` through `zinc-950`)
- **Typography**: Inter (sans-serif) paired with JetBrains Mono (monospace)
- **Icons & Data Fetching**: `lucide-react` for iconography, `swr` for real-time polling (10s interval)

### 2. Dashboard View (`/`)
- **Real-Time Deployment Grid**: Displays all provisioned sites with live status indicators (`AVAILABLE`, `PROVISIONING`, `DESTROYING`, `FAILED`).
- **Site Metadata**: Shows internal Site ID, Domain name with direct link, and compute instance sizing.
- **Deploy Modal (`[+ Deploy Site]`)**: Enables non-technical users to enter a `site_id` and target domain to trigger automated end-to-end AWS provisioning via `POST /sites`.
- **Destruction Trigger (`[DEL]`)**: Prompts for confirmation and triggers asynchronous teardown via `DELETE /sites/{site_id}`.

### 3. Site Detail & Telemetry View (`/sites/[site_id]`)
- **Live Health Metrics**: Visualizes findings collected by Phase 5 continuous monitoring:
  - **Storage IO**: Real-time disk utilization (`df -h`).
  - **Core Version**: WordPress core version status and available updates count.
  - **Module Updates**: WordPress plugin updates count.
  - **Cert Validity**: SSL certificate days remaining or ACM-managed badge.
- **Operational Controls**:
  - **Restart Instance**: Triggers instant EC2 reboot via `POST /sites/{site_id}/reboot`.
  - **Run Backup**: Triggers EBS snapshot and RDS automated snapshot via `POST /sites/{site_id}/backup`.

### 4. API & Orchestrator Integration
- Communicates with AWS API Gateway (`https://yd1h3zhgqf.execute-api.us-east-1.amazonaws.com`).
- CORS support configured on the API Gateway V2 HTTP API (`cors_configuration`) allowing cross-origin requests from the browser dashboard.
- Custom `DecimalEncoder` implemented in the API Lambda to prevent serialization errors when retrieving DynamoDB numeric metrics.

## Verification

1. **Non-Technical Deployment**: Users can launch sites directly from the UI modal without shell/terminal access.
2. **Real-Time Polling**: Status updates from `PROVISIONING` to `AVAILABLE` automatically without manual page refreshes.
3. **Operational Actions**: Successfully initiates server reboots and automated backups through UI button clicks.
