$ErrorActionPreference = "Stop"

$AWS_ACCESS_KEY_ID = aws configure get aws_access_key_id
$AWS_SECRET_ACCESS_KEY = aws configure get aws_secret_access_key

# Make sure we got them
if ([string]::IsNullOrEmpty($AWS_ACCESS_KEY_ID)) {
    throw "AWS_ACCESS_KEY_ID is missing"
}

$env:INSTANCE_ID = terraform -chdir=d:\Cloudpress\terraform\environments\dev3 output -raw ec2_instance_id
$env:RDS_ENDPOINT = terraform -chdir=d:\Cloudpress\terraform\environments\dev3 output -raw rds_endpoint
$env:DB_HOST = $env:RDS_ENDPOINT.Split(":")[0]
$env:ALB_DNS = terraform -chdir=d:\Cloudpress\terraform\environments\dev3 output -raw alb_dns_name

$env:AWS_ACCESS_KEY_ID = $AWS_ACCESS_KEY_ID
$env:AWS_SECRET_ACCESS_KEY = $AWS_SECRET_ACCESS_KEY
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:AWS_REGION = "us-east-1"

$env:WSLENV = "AWS_ACCESS_KEY_ID/u:AWS_SECRET_ACCESS_KEY/u:AWS_DEFAULT_REGION/u:AWS_REGION/u:INSTANCE_ID/u:DB_HOST/u"

wsl -u root bash -c "mkdir -p ~/.aws && echo -e '[default]\naws_access_key_id='`$AWS_ACCESS_KEY_ID'\naws_secret_access_key='`$AWS_SECRET_ACCESS_KEY'\nregion=us-east-1' > ~/.aws/credentials"
wsl -u root bash ./run-wsl.sh
