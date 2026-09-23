import os
import json
import boto3
import time
import socket
import ssl
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
ec2 = boto3.client('ec2')
rds = boto3.client('rds')
ssm = boto3.client('ssm')

TABLE_NAME = os.environ.get('TABLE_NAME', 'cloudpress-sites')
table = dynamodb.Table(TABLE_NAME)

def cleanup_old_backups(site_id, retention_days=7):
    cutoff_time = time.time() - (retention_days * 86400)
    
    # 1. Clean old AMIs and underlying EBS snapshots
    try:
        images = ec2.describe_images(
            Owners=['self'],
            Filters=[{'Name': 'name', 'Values': [f'cloudpress-backup-{site_id}-*']}]
        ).get('Images', [])
        
        for img in images:
            try:
                creation_dt = datetime.strptime(img['CreationDate'][:19], '%Y-%m-%dT%H:%M:%S')
                creation_ts = creation_dt.timestamp()
                if creation_ts < cutoff_time:
                    print(f"Pruning expired AMI {img['ImageId']} ({img['Name']}) for {site_id}")
                    snap_ids = []
                    for bdm in img.get('BlockDeviceMappings', []):
                        ebs = bdm.get('Ebs', {})
                        if 'SnapshotId' in ebs:
                            snap_ids.append(ebs['SnapshotId'])
                            
                    ec2.deregister_image(ImageId=img['ImageId'])
                    
                    for snap_id in snap_ids:
                        try:
                            ec2.delete_snapshot(SnapshotId=snap_id)
                        except Exception as se:
                            print(f"Error deleting snapshot {snap_id}: {se}")
            except Exception as e:
                print(f"Error evaluating AMI {img.get('ImageId')}: {e}")
    except Exception as e:
        print(f"Error cleaning old AMIs for {site_id}: {e}")

    # 2. Clean old RDS Snapshots
    try:
        db_id = f'cloudpress-db-{site_id}'
        snapshots = rds.describe_db_snapshots(
            DBInstanceIdentifier=db_id,
            SnapshotType='manual'
        ).get('DBSnapshots', [])
        
        for snap in snapshots:
            snap_id = snap['DBSnapshotIdentifier']
            if not snap_id.startswith(f'cloudpress-db-backup-{site_id}-'):
                continue
            create_time = snap.get('SnapshotCreateTime')
            if create_time and create_time.timestamp() < cutoff_time:
                print(f"Pruning expired RDS snapshot {snap_id}")
                try:
                    rds.delete_db_snapshot(DBSnapshotIdentifier=snap_id)
                except Exception as se:
                    print(f"Error deleting RDS snapshot {snap_id}: {se}")
    except Exception as e:
        print(f"Error cleaning old RDS snapshots for {site_id}: {e}")

def perform_daily_backup_if_needed(site_id, instance_id, site):
    last_backup = site.get('last_backup_time')
    now = time.time()
    # Trigger if no backup recorded or > 24 hours have elapsed
    if not last_backup or (now - float(last_backup)) >= 86400:
        print(f"Triggering daily automated backup for {site_id}...")
        ts = str(int(now))
        ami_name = f'cloudpress-backup-{site_id}-{ts}'
        snap_name = f'cloudpress-db-backup-{site_id}-{ts}'
        
        try:
            ec2.create_image(InstanceId=instance_id, Name=ami_name, NoReboot=True)
            print(f"Initiated AMI {ami_name}")
        except Exception as e:
            print(f"Daily backup EC2 AMI error for {site_id}: {e}")
            
        try:
            db_id = f'cloudpress-db-{site_id}'
            rds.create_db_snapshot(
                DBSnapshotIdentifier=snap_name,
                DBInstanceIdentifier=db_id
            )
            print(f"Initiated RDS snapshot {snap_name}")
        except Exception as e:
            print(f"Daily backup RDS snapshot error for {site_id}: {e}")
            
        try:
            table.update_item(
                Key={'site_id': site_id},
                UpdateExpression='SET last_backup_time = :btime',
                ExpressionAttributeValues={':btime': ts}
            )
        except Exception as e:
            print(f"Failed to record last_backup_time for {site_id}: {e}")
            
        # Prune snapshots older than 7 days
        cleanup_old_backups(site_id, retention_days=7)

def get_ssl_expiry_days(domain):
    try:
        context = ssl.create_default_context()
        with socket.create_connection((domain, 443), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname=domain) as ssock:
                cert = ssock.getpeercert()
                expiry_str = cert['notAfter']
                expiry_date = datetime.strptime(expiry_str, '%b %d %H:%M:%S %Y %Z')
                delta = expiry_date - datetime.utcnow()
                return delta.days
    except Exception as e:
        print(f"SSL error for {domain}: {e}")
        return -1

def run_ssm_command(instance_id, commands):
    try:
        cmd = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': commands}
        )
        command_id = cmd['Command']['CommandId']
        
        retries = 10
        while retries > 0:
            time.sleep(2)
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
            if result['Status'] not in ['Pending', 'InProgress']:
                return result.get('StandardOutputContent', '').strip()
            retries -= 1
        return ""
    except Exception as e:
        print(f"SSM error for {instance_id}: {e}")
        return ""

def handler(event, context):
    try:
        response = table.scan()
        sites = response.get('Items', [])
        
        for site in sites:
            try:
                if site.get('status') != 'AVAILABLE':
                    continue
                    
                site_id = site['site_id']
                domain = site.get('domain', '')
                if not domain:
                    print(f"Skipping {site_id} - no domain configured")
                    continue
                
                print(f"Monitoring {site_id}...")
            
                # Find EC2 Instance
                res = ec2.describe_instances(Filters=[
                    {'Name': 'tag:Name', 'Values': [f'cloudpress-ec2-{site_id}']},
                    {'Name': 'instance-state-name', 'Values': ['running']}
                ])
                instance_id = None
                for resv in res.get('Reservations', []):
                    for inst in resv.get('Instances', []):
                        instance_id = inst['InstanceId']
                
                metrics = {
                    'last_checked': str(int(time.time())),
                    'ssl_days_remaining': get_ssl_expiry_days(domain)
                }
                
                if instance_id:
                    # Disk Usage
                    disk_out = run_ssm_command(instance_id, ["df -h / | tail -1 | awk '{print $5}'"])
                    metrics['disk_usage'] = disk_out
                    
                    # WP Core updates
                    core_out = run_ssm_command(instance_id, ["sudo -u www-data wp core check-update --path=/var/www/" + domain + " --format=json"])
                    try:
                        core_json = json.loads(core_out)
                        metrics['core_updates'] = len(core_json)
                    except:
                        metrics['core_updates'] = 0
                    
                    # WP Plugin updates
                    plugin_out = run_ssm_command(instance_id, ["sudo -u www-data wp plugin list --update=available --format=json --path=/var/www/" + domain])
                    try:
                        plugin_json = json.loads(plugin_out)
                        metrics['plugin_updates'] = len(plugin_json)
                    except:
                        metrics['plugin_updates'] = 0
                        
                    # Admin users
                    admin_out = run_ssm_command(instance_id, ["sudo -u www-data wp user list --role=administrator --format=json --path=/var/www/" + domain])
                    try:
                        admin_json = json.loads(admin_out)
                        metrics['admins'] = [a['user_login'] for a in admin_json]
                    except:
                        metrics['admins'] = []

                    # Automated daily snapshot & 7-day retention
                    try:
                        perform_daily_backup_if_needed(site_id, instance_id, site)
                    except Exception as b_err:
                        print(f"Daily backup execution error for {site_id}: {b_err}")
                
                # Update DynamoDB
                table.update_item(
                    Key={'site_id': site_id},
                    UpdateExpression='SET health_metrics = :val',
                    ExpressionAttributeValues={':val': metrics}
                )
            except Exception as site_err:
                print(f"Error monitoring {site.get('site_id')}: {site_err}")
            
        return {'statusCode': 200, 'body': 'Monitoring complete'}
    except Exception as e:
        print(f"Monitor error: {e}")
        return {'statusCode': 500, 'body': str(e)}
