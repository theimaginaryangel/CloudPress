import os
import json
import boto3
import time
from decimal import Decimal
from botocore.exceptions import ClientError

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def dumps(obj):
    return json.dumps(obj, cls=DecimalEncoder)


dynamodb = boto3.resource('dynamodb')
codebuild = boto3.client('codebuild')
ec2 = boto3.client('ec2')
rds = boto3.client('rds')
ssm = boto3.client('ssm')
elbv2 = boto3.client('elbv2')

TABLE_NAME = os.environ.get('TABLE_NAME', 'cloudpress-sites')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'cloudpress-orchestrator')

table = dynamodb.Table(TABLE_NAME)

def get_alb_map():
    try:
        lbs = elbv2.describe_load_balancers().get('LoadBalancers', [])
        alb_map = {}
        for lb in lbs:
            name = lb.get('LoadBalancerName', '')
            if name.startswith('cloudpress-alb-'):
                sid = name.replace('cloudpress-alb-', '')
                alb_map[sid] = lb.get('DNSName', '')
        return alb_map
    except Exception as e:
        print(f"Error fetching ALBs: {e}")
        return {}

def get_instance_id(site_id):
    res = ec2.describe_instances(Filters=[
        {'Name': 'tag:Name', 'Values': [f'cloudpress-ec2-{site_id}']},
        {'Name': 'instance-state-name', 'Values': ['running', 'stopped']}
    ])
    for resv in res.get('Reservations', []):
        for inst in resv.get('Instances', []):
            return inst['InstanceId']
    return None

def get_sites(event):
    response = table.scan()
    items = response.get('Items', [])
    alb_map = get_alb_map()
    for item in items:
        sid = item.get('site_id')
        if sid in alb_map:
            item['alb_dns_name'] = alb_map[sid]
            item['public_url'] = f"http://{alb_map[sid]}"
    return {'statusCode': 200, 'body': dumps(items)}

def get_site(event, site_id):
    response = table.get_item(Key={'site_id': site_id})
    if 'Item' in response:
        item = response['Item']
        alb_map = get_alb_map()
        if site_id in alb_map:
            item['alb_dns_name'] = alb_map[site_id]
            item['public_url'] = f"http://{alb_map[site_id]}"
        return {'statusCode': 200, 'body': dumps(item)}
    return {'statusCode': 404, 'body': dumps({'error': 'Site not found'})}

def create_site(event):
    body = json.loads(event.get('body', '{}'))
    site_id = body.get('site_id')
    domain = body.get('domain')
    instance_size = body.get('instance_size', 't3.micro')
    
    if not site_id or not domain:
        return {'statusCode': 400, 'body': dumps({'error': 'Missing site_id or domain'})}
        
    response = table.get_item(Key={'site_id': site_id})
    if 'Item' in response:
        return {'statusCode': 400, 'body': dumps({'error': 'Site already exists'})}
        
    item = {
        'site_id': site_id,
        'domain': domain,
        'instance_size': instance_size,
        'status': 'PROVISIONING',
        'created_at': str(int(time.time()))
    }
    table.put_item(Item=item)
    
    try:
        codebuild.start_build(
            projectName=PROJECT_NAME,
            environmentVariablesOverride=[
                {'name': 'SITE_ID', 'value': site_id, 'type': 'PLAINTEXT'},
                {'name': 'DOMAIN', 'value': domain, 'type': 'PLAINTEXT'},
                {'name': 'INSTANCE_SIZE', 'value': instance_size, 'type': 'PLAINTEXT'},
                {'name': 'ACTION', 'value': 'PROVISION', 'type': 'PLAINTEXT'},
                {'name': 'STATE_BUCKET', 'value': os.environ.get('STATE_BUCKET', ''), 'type': 'PLAINTEXT'}
            ]
        )
    except ClientError as e:
        table.update_item(
            Key={'site_id': site_id},
            UpdateExpression='SET #status = :val',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':val': 'FAILED_TO_START'}
        )
        return {'statusCode': 500, 'body': dumps({'error': str(e)})}
        
    return {'statusCode': 202, 'body': dumps(item)}

def delete_site(event, site_id):
    response = table.get_item(Key={'site_id': site_id})
    if 'Item' not in response:
        return {'statusCode': 404, 'body': dumps({'error': 'Site not found'})}
        
    item = response['Item']
    
    table.update_item(
        Key={'site_id': site_id},
        UpdateExpression='SET #status = :val',
        ExpressionAttributeNames={'#status': 'status'},
        ExpressionAttributeValues={':val': 'DESTROYING'}
    )
    
    try:
        codebuild.start_build(
            projectName=PROJECT_NAME,
            environmentVariablesOverride=[
                {'name': 'SITE_ID', 'value': site_id, 'type': 'PLAINTEXT'},
                {'name': 'DOMAIN', 'value': item.get('domain', ''), 'type': 'PLAINTEXT'},
                {'name': 'INSTANCE_SIZE', 'value': item.get('instance_size', 't3.micro'), 'type': 'PLAINTEXT'},
                {'name': 'ACTION', 'value': 'DESTROY', 'type': 'PLAINTEXT'},
                {'name': 'STATE_BUCKET', 'value': os.environ.get('STATE_BUCKET', ''), 'type': 'PLAINTEXT'}
            ]
        )
    except ClientError as e:
        table.update_item(
            Key={'site_id': site_id},
            UpdateExpression='SET #status = :val',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':val': 'FAILED'}
        )
        return {'statusCode': 500, 'body': dumps({'error': str(e)})}
        
    return {'statusCode': 202, 'body': dumps({'message': 'Destroy initiated'})}

def reboot_site(event, site_id):
    inst_id = get_instance_id(site_id)
    if not inst_id:
        return {'statusCode': 404, 'body': dumps({'error': 'Instance not found'})}
    try:
        ec2.reboot_instances(InstanceIds=[inst_id])
        return {'statusCode': 200, 'body': dumps({'message': 'Reboot initiated', 'instance_id': inst_id})}
    except ClientError as e:
        return {'statusCode': 500, 'body': dumps({'error': str(e)})}

def get_site_logs(event, site_id):
    inst_id = get_instance_id(site_id)
    if not inst_id:
        return {'statusCode': 404, 'body': json.dumps({'error': 'Instance not found'})}
    
    try:
        # Send SSM Command
        cmd = ssm.send_command(
            InstanceIds=[inst_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': ['tail -n 100 /var/log/nginx/access.log']}
        )
        command_id = cmd['Command']['CommandId']
        
        # Wait a bit for execution
        time.sleep(2)
        
        # Get output
        result = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=inst_id
        )
        # Ssm might still be InProgress, ideally we wait loop
        retries = 5
        while result['Status'] in ['Pending', 'InProgress'] and retries > 0:
            time.sleep(2)
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=inst_id)
            retries -= 1
            
        return {'statusCode': 200, 'body': dumps({
            'status': result['Status'],
            'logs': result.get('StandardOutputContent', '') + result.get('StandardErrorContent', '')
        })}
    except ClientError as e:
        return {'statusCode': 500, 'body': dumps({'error': str(e)})}

def backup_site(event, site_id):
    inst_id = get_instance_id(site_id)
    if not inst_id:
        return {'statusCode': 404, 'body': dumps({'error': 'Instance not found'})}
        
    timestamp = str(int(time.time()))
    ami_name = f'cloudpress-backup-{site_id}-{timestamp}'
    snap_name = f'cloudpress-db-backup-{site_id}-{timestamp}'
    
    res = {}
    # EC2
    try:
        image = ec2.create_image(InstanceId=inst_id, Name=ami_name, NoReboot=True)
        res['ami_id'] = image['ImageId']
    except ClientError as e:
        res['ami_error'] = str(e)
        
    # RDS
    try:
        db_id = f'cloudpress-db-{site_id}'
        snap = rds.create_db_snapshot(
            DBSnapshotIdentifier=snap_name,
            DBInstanceIdentifier=db_id
        )
        res['db_snapshot_id'] = snap['DBSnapshot']['DBSnapshotIdentifier']
    except ClientError as e:
        res['db_error'] = str(e)
        
    return {'statusCode': 202, 'body': dumps(res)}

def handler(event, context):
    try:
        print("Received event:", dumps(event))
        route_key = event.get('routeKey')
        if not route_key:
            http_method = event.get('httpMethod', '')
            resource = event.get('resource', '')
            if http_method and resource:
                route_key = f"{http_method} {resource}"
            else:
                route_key = ""
        
        path_params = event.get('pathParameters') or {}
        site_id = path_params.get('site_id')
        
        if route_key == 'GET /sites':
            return get_sites(event)
        elif route_key == 'GET /sites/{site_id}':
            return get_site(event, site_id)
        elif route_key == 'POST /sites':
            return create_site(event)
        elif route_key == 'DELETE /sites/{site_id}':
            return delete_site(event, site_id)
        elif route_key == 'POST /sites/{site_id}/reboot':
            return reboot_site(event, site_id)
        elif route_key == 'GET /sites/{site_id}/logs':
            return get_site_logs(event, site_id)
        elif route_key == 'POST /sites/{site_id}/backup':
            return backup_site(event, site_id)
        else:
            return {'statusCode': 404, 'body': dumps({'error': f"Route {route_key} not found"})}
            
    except Exception as e:
        return {'statusCode': 500, 'body': dumps({'error': str(e)})}
