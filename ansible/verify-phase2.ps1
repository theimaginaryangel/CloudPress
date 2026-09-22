$ErrorActionPreference = "Stop"

Write-Host "Creating clean dev3 environment..."
if (Test-Path "d:\Cloudpress\terraform\environments\dev3") { Remove-Item -Recurse -Force "d:\Cloudpress\terraform\environments\dev3" }
Copy-Item -Path "d:\Cloudpress\terraform\environments\dev" -Destination "d:\Cloudpress\terraform\environments\dev3" -Recurse -Force
Remove-Item -Path "d:\Cloudpress\terraform\environments\dev3\terraform.tfstate*" -Force -ErrorAction SilentlyContinue

Write-Host "Applying Phase 1 Infrastructure (Site 3)..."
cd d:\Cloudpress\terraform\environments\dev3
terraform init
terraform apply -auto-approve

Write-Host "Fetching Outputs..."
$INSTANCE_ID = terraform output -raw ec2_instance_id
$RDS_ENDPOINT = terraform output -raw rds_endpoint
$ALB_DNS = terraform output -raw alb_dns_name
$DB_HOST = $RDS_ENDPOINT.Split(":")[0]

cd d:\Cloudpress\ansible

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
$env:AWS_REGION = $AWS_REGION
$env:INSTANCE_ID = $INSTANCE_ID
$env:DB_HOST = $DB_HOST

$env:WSLENV = "AWS_ACCESS_KEY_ID/u:AWS_SECRET_ACCESS_KEY/u:AWS_SESSION_TOKEN/u:AWS_REGION/u:INSTANCE_ID/u:DB_HOST/u"

try {
    wsl -u root bash ./run-wsl.sh

    Write-Host "Verifying WordPress Installation at $ALB_DNS..."
    for ($i=0; $i -lt 12; $i++) {
        Write-Host "Attempt $($i+1): Fetching http://$ALB_DNS ..."
        $RESPONSE = Invoke-WebRequest -Uri "http://$ALB_DNS" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($RESPONSE -and $RESPONSE.StatusCode -eq 200) {
            Write-Host "WordPress is reachable!"
            break
        }
        Start-Sleep -Seconds 10
    }
} finally {
    Write-Host "Tearing down Infrastructure..."
    cd d:\Cloudpress\terraform\environments\dev3
    terraform destroy -auto-approve
    Write-Host "Phase 2 Verification Complete."
}
