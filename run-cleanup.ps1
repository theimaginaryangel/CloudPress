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
$env:AWS_DEFAULT_REGION = $AWS_REGION

wsl -u root bash ./cleanup-orphans.sh
