$ErrorActionPreference = "Stop"

Write-Host "Applying Phase 1 Infrastructure (Site 3)..."
cd d:\Cloudpress\terraform\environments\dev3
terraform apply -auto-approve

Write-Host "Fetching Outputs..."
$INSTANCE_ID = terraform output -raw ec2_instance_id
$RDS_ENDPOINT = terraform output -raw rds_endpoint
$ALB_DNS = terraform output -raw alb_dns_name
$DB_HOST = $RDS_ENDPOINT.Split(":")[0]

cd d:\Cloudpress\ansible

Write-Host "Downloading session-manager-plugin.deb on Windows..."
Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -OutFile "session-manager-plugin.deb" -UseBasicParsing

Write-Host "Installing session-manager-plugin in WSL..."
wsl -u root bash -c "dpkg -i /mnt/d/Cloudpress/ansible/session-manager-plugin.deb"

Write-Host "Running Ansible Playbook against $INSTANCE_ID via WSL..."
$AWS_ACCESS_KEY_ID = aws configure get aws_access_key_id
$AWS_SECRET_ACCESS_KEY = aws configure get aws_secret_access_key
$AWS_SESSION_TOKEN = aws configure get aws_session_token
$AWS_REGION = aws configure get region

if ([string]::IsNullOrEmpty($AWS_REGION)) {
    $AWS_REGION = "us-east-1"
}

$env:AWS_ACCESS_KEY_ID = $AWS_ACCESS_KEY_ID
$env:AWS_SECRET_ACCESS_KEY = $AWS_SECRET_ACCESS_KEY
$env:AWS_SESSION_TOKEN = $AWS_SESSION_TOKEN
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:AWS_REGION = "us-east-1"
$env:INSTANCE_ID = $INSTANCE_ID
$env:DB_HOST = $DB_HOST

$env:WSLENV = "AWS_ACCESS_KEY_ID/u:AWS_SECRET_ACCESS_KEY/u:AWS_DEFAULT_REGION/u:AWS_REGION/u:INSTANCE_ID/u:DB_HOST/u"

wsl -u root bash -c "mkdir -p ~/.aws && echo -e '[default]\naws_access_key_id='`$AWS_ACCESS_KEY_ID'\naws_secret_access_key='`$AWS_SECRET_ACCESS_KEY'\nregion=us-east-1' > ~/.aws/credentials"
wsl -u root bash /mnt/d/Cloudpress/ansible/run-wsl.sh

Write-Host "Verifying WordPress Installation at $ALB_DNS..."
for ($i=0; $i -lt 15; $i++) {
    Write-Host "Attempt $($i+1): Fetching http://$ALB_DNS ..."
    try {
        $RESPONSE = Invoke-WebRequest -Uri "http://$ALB_DNS" -UseBasicParsing -ErrorAction Stop
        if ($RESPONSE.StatusCode -eq 200) {
            Write-Host "WordPress is reachable!"
            break
        }
    } catch {
        Write-Host "Not ready yet... HTTP status: $($_.Exception.Response.StatusCode)"
    }
    Start-Sleep -Seconds 10
}
