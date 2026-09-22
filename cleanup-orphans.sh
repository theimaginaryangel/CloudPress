#!/bin/bash
export AWS_DEFAULT_REGION="us-east-1"

echo "Cleaning up orphans..."

# Delete DBs
dbs=$(/usr/local/bin/aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `cloudpress-db`)].DBInstanceIdentifier' --output text)
for db in $dbs; do
    echo "Deleting DB $db"
    /usr/local/bin/aws rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot || true
done

# Delete ALB
albs=$(/usr/local/bin/aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `cloudpress-alb`)].LoadBalancerArn' --output text)
for alb in $albs; do
    echo "Deleting ALB $alb"
    /usr/local/bin/aws elbv2 delete-load-balancer --load-balancer-arn "$alb" || true
done

# Delete Target Groups
tgs=$(/usr/local/bin/aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `cloudpress-tg`)].TargetGroupArn' --output text)
for tg in $tgs; do
    echo "Deleting Target Group $tg"
    /usr/local/bin/aws elbv2 delete-target-group --target-group-arn "$tg" || true
done

# Delete IAM Roles
roles=$(/usr/local/bin/aws iam list-roles --query 'Roles[?contains(RoleName, `cloudpress-ec2-role`)].RoleName' --output text)
for role in $roles; do
    echo "Deleting Role $role"
    # detach policies
    policies=$(/usr/local/bin/aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for pol in $policies; do
        /usr/local/bin/aws iam detach-role-policy --role-name "$role" --policy-arn "$pol" || true
    done
    
    # remove instance profiles
    profiles=$(/usr/local/bin/aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[*].InstanceProfileName' --output text)
    for prof in $profiles; do
        /usr/local/bin/aws iam remove-role-from-instance-profile --instance-profile-name "$prof" --role-name "$role" || true
        /usr/local/bin/aws iam delete-instance-profile --instance-profile-name "$prof" || true
    done

    /usr/local/bin/aws iam delete-role --role-name "$role" || true
done

# Delete IAM Policies
policies=$(/usr/local/bin/aws iam list-policies --scope Local --query 'Policies[?contains(PolicyName, `cloudpress-`)].Arn' --output text)
for pol in $policies; do
    echo "Deleting Policy $pol"
    /usr/local/bin/aws iam delete-policy --policy-arn "$pol" || true
done

# Delete Secrets
secrets=$(/usr/local/bin/aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `cloudpress/db/`)].Name' --output text)
for sec in $secrets; do
    echo "Deleting Secret $sec"
    /usr/local/bin/aws secretsmanager delete-secret --secret-id "$sec" --force-delete-without-recovery || true
done

echo "Done cleanup."
