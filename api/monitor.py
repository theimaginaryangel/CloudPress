import os
import json
import boto3
import time
import socket
import ssl
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

TABLE_NAME = os.environ.get('TABLE_NAME', 'cloudpress-sites')
table = dynamodb.Table(TABLE_NAME)

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
            if site.get('status') != 'AVAILABLE':
                continue
                
            site_id = site['site_id']
            domain = site['domain']
            
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
            
            # Update DynamoDB
            table.update_item(
                Key={'site_id': site_id},
                UpdateExpression='SET health_metrics = :val',
                ExpressionAttributeValues={':val': metrics}
            )
            
        return {'statusCode': 200, 'body': 'Monitoring complete'}
    except Exception as e:
        print(f"Monitor error: {e}")
        return {'statusCode': 500, 'body': str(e)}
