import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = "AutoSchedule"
TAG_VALUE = "true"


def get_tagged_ec2_instances(ec2_client, action):
    """Return instance IDs tagged for scheduling that are in a valid state for the action."""
    target_state = "stopped" if action == "start" else "running"
    response = ec2_client.describe_instances(
        Filters=[
            {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
            {"Name": "instance-state-name", "Values": [target_state]},
        ]
    )
    instance_ids = []
    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instance_ids.append(instance["InstanceId"])
    return instance_ids


def get_tagged_rds_instances(rds_client, action):
    """Return RDS instance identifiers tagged for scheduling that are in a valid state."""
    target_status = "stopped" if action == "start" else "available"
    response = rds_client.describe_db_instances()
    db_identifiers = []
    for db in response["DBInstances"]:
        if db["DBInstanceStatus"] != target_status:
            continue
        arn = db["DBInstanceArn"]
        tags_response = rds_client.list_tags_for_resource(ResourceName=arn)
        for tag in tags_response["TagList"]:
            if tag["Key"] == TAG_KEY and tag["Value"] == TAG_VALUE:
                db_identifiers.append(db["DBInstanceIdentifier"])
                break
    return db_identifiers


def handle_ec2(ec2_client, action, instance_ids):
    """Start or stop EC2 instances, logging per-instance results."""
    if not instance_ids:
        logger.info("No EC2 instances to %s", action)
        return []

    results = []
    for instance_id in instance_ids:
        try:
            if action == "start":
                ec2_client.start_instances(InstanceIds=[instance_id])
            else:
                ec2_client.stop_instances(InstanceIds=[instance_id])
            logger.info("EC2 %s: %s - SUCCESS", action, instance_id)
            results.append({"id": instance_id, "status": "success"})
        except Exception as e:
            logger.error("EC2 %s: %s - FAILED: %s", action, instance_id, str(e))
            results.append({"id": instance_id, "status": "failed", "error": str(e)})
    return results


def handle_rds(rds_client, action, db_identifiers):
    """Start or stop RDS instances, logging per-instance results."""
    if not db_identifiers:
        logger.info("No RDS instances to %s", action)
        return []

    results = []
    for db_id in db_identifiers:
        try:
            if action == "start":
                rds_client.start_db_instance(DBInstanceIdentifier=db_id)
            else:
                rds_client.stop_db_instance(DBInstanceIdentifier=db_id)
            logger.info("RDS %s: %s - SUCCESS", action, db_id)
            results.append({"id": db_id, "status": "success"})
        except Exception as e:
            logger.error("RDS %s: %s - FAILED: %s", action, db_id, str(e))
            results.append({"id": db_id, "status": "failed", "error": str(e)})
    return results


def lambda_handler(event, context):
    action = event.get("action")
    if action not in ("start", "stop"):
        logger.error("Invalid action: %s. Must be 'start' or 'stop'.", action)
        return {"statusCode": 400, "body": "Invalid action"}

    logger.info("Scheduler triggered - action: %s", action)

    ec2_client = boto3.client("ec2")
    rds_client = boto3.client("rds")

    ec2_ids = get_tagged_ec2_instances(ec2_client, action)
    rds_ids = get_tagged_rds_instances(rds_client, action)

    logger.info("Found %d EC2 instance(s) and %d RDS instance(s) to %s",
                len(ec2_ids), len(rds_ids), action)

    ec2_results = handle_ec2(ec2_client, action, ec2_ids)
    rds_results = handle_rds(rds_client, action, rds_ids)

    summary = {
        "action": action,
        "ec2": ec2_results,
        "rds": rds_results,
    }
    logger.info("Summary: %s", json.dumps(summary))

    return {"statusCode": 200, "body": json.dumps(summary)}
