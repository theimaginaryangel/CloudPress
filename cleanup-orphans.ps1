$ErrorActionPreference = "Continue"

Write-Host "Cleaning up orphans..."

# DBs
$dbs = (aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `cloudpress-db`)].DBInstanceIdentifier' --output text) -split '\s+' | Where-Object { $_ }
foreach ($db in $dbs) {
    Write-Host "Deleting DB $db"
    aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot
}

# ALBs
$albs = (aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `cloudpress-alb`)].LoadBalancerArn' --output text) -split '\s+' | Where-Object { $_ }
foreach ($alb in $albs) {
    Write-Host "Deleting ALB $alb"
    aws elbv2 delete-load-balancer --load-balancer-arn $alb
}

# Target Groups
$tgs = (aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `cloudpress-tg`)].TargetGroupArn' --output text) -split '\s+' | Where-Object { $_ }
foreach ($tg in $tgs) {
    Write-Host "Deleting Target Group $tg"
    aws elbv2 delete-target-group --target-group-arn $tg
}

# IAM Roles
$roles = (aws iam list-roles --query 'Roles[?contains(RoleName, `cloudpress-ec2-role`)].RoleName' --output text) -split '\s+' | Where-Object { $_ }
foreach ($role in $roles) {
    Write-Host "Deleting Role $role"
    $policies = (aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[*].PolicyArn' --output text) -split '\s+' | Where-Object { $_ }
    foreach ($pol in $policies) {
        $pol = $pol.Trim()
        if ($pol) { aws iam detach-role-policy --role-name $role --policy-arn $pol }
    }
    
    $profiles = (aws iam list-instance-profiles-for-role --role-name $role --query 'InstanceProfiles[*].InstanceProfileName' --output text) -split '\s+' | Where-Object { $_ }
    foreach ($prof in $profiles) {
        $prof = $prof.Trim()
        if ($prof) { 
            aws iam remove-role-from-instance-profile --instance-profile-name $prof --role-name $role
            aws iam delete-instance-profile --instance-profile-name $prof 
        }
    }
    aws iam delete-role --role-name $role
}

# IAM Policies
$policies = (aws iam list-policies --scope Local --query 'Policies[?contains(PolicyName, `cloudpress-`)].Arn' --output text) -split '\s+' | Where-Object { $_ }
foreach ($pol in $policies) {
    Write-Host "Deleting Policy $pol"
    aws iam delete-policy --policy-arn $pol
}

# Secrets
$secrets = (aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `cloudpress/db/`)].Name' --output text) -split '\s+' | Where-Object { $_ }
foreach ($sec in $secrets) {
    Write-Host "Deleting Secret $sec"
    aws secretsmanager delete-secret --secret-id $sec --force-delete-without-recovery
}

Write-Host "Done cleanup."
