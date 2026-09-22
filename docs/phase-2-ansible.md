# Phase 2: Configuration Management (Ansible)

## Overview
Phase 2 implements the configuration management layer using Ansible. It is responsible for taking a raw, newly provisioned Ubuntu EC2 instance and configuring it to run a production-grade WordPress site. It strictly uses AWS Systems Manager (SSM) for connection instead of direct SSH, keeping our instances in private subnets without public IPs.

## Architecture
- **Web Server**: Nginx
- **Application**: WordPress (latest)
- **Database**: Connects to the RDS MySQL instance provisioned in Phase 1
- **Connection Plugin**: ws_ssm

## Key Components

### 1. The Playbook (nsible/playbooks/site.yml)
The main entrypoint playbook that orchestrates the configuration. It assigns the wordpress role to all target hosts.

### 2. The WordPress Role (nsible/roles/wordpress/)
This role encapsulates all the tasks required to install and configure WordPress:
- 	asks/main.yml: The execution order.
- 	asks/nginx.yml: Installs Nginx and configures the virtual host (domain).
- 	asks/php.yml: Installs PHP-FPM and necessary extensions.
- 	asks/wordpress.yml: Downloads WordPress, extracts it, and configures wp-config.php dynamically using provided variables (database credentials, salts).

### 3. Connection via SSM
We use the ws_ssm connection plugin provided by the mazon.aws collection. This allows Ansible to execute commands over the SSM Session Manager tunnel without opening port 22 on the EC2 instances.

## Variables
The playbook expects the following variables to be provided at runtime (typically generated and passed by the Orchestration layer via nsible_vars.json):
- domain: The domain name for the WordPress site.
- db_name: The WordPress database name.
- db_user: The RDS database username.
- db_password: The RDS database password.
- db_host: The RDS database endpoint.
