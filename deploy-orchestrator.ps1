# 1. Deploy Orchestration Infrastructure
Set-Location "d:\Cloudpress\terraform\environments\orchestration"
terraform init
terraform apply -auto-approve

# 2. Get Outputs
$SOURCE_BUCKET = terraform output -raw source_bucket
$API_ENDPOINT = terraform output -raw api_endpoint

# 3. Zip and Upload Codebase
Set-Location "d:\Cloudpress"
Remove-Item -Path "source.zip" -ErrorAction SilentlyContinue

# Compress-Archive has no exclude feature, so we will create a staging folder.
New-Item -ItemType Directory -Force -Path "staging"
Copy-Item -Path "api" -Destination "staging" -Recurse
Copy-Item -Path "terraform" -Destination "staging" -Recurse
Copy-Item -Path "ansible" -Destination "staging" -Recurse

# Remove terraform state files and large hidden dirs
Get-ChildItem -Path "staging\terraform" -Recurse -Filter ".terraform" -Directory | Remove-Item -Recurse -Force
Get-ChildItem -Path "staging\terraform" -Recurse -Filter "*.tfstate*" | Remove-Item -Force

python zip_code.py
Remove-Item -Path "staging" -Recurse -Force

aws s3 cp source.zip s3://$SOURCE_BUCKET/source.zip

Write-Host "Deployment complete! API Endpoint: $API_ENDPOINT"
