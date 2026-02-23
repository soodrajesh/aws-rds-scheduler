import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = "AlwaysStopRDS"
TAG_VALUE = "true"


def get_running_tagged_rds_instances(rds_client):
    """Return RDS instance identifiers that are running and tagged AlwaysStopRDS=true."""
    response = rds_client.describe_db_instances()
    db_identifiers = []
    for db in response["DBInstances"]:
        if db["DBInstanceStatus"] != "available":
            continue
        arn = db["DBInstanceArn"]
        tags_response = rds_client.list_tags_for_resource(ResourceName=arn)
        for tag in tags_response["TagList"]:
            if tag["Key"] == TAG_KEY and tag["Value"] == TAG_VALUE:
                db_identifiers.append(db["DBInstanceIdentifier"])
                break
    return db_identifiers


def stop_rds_instances(rds_client, db_identifiers):
    """Stop each RDS instance individually so one failure doesn't block others."""
    if not db_identifiers:
        logger.info("No RDS instances to stop - all tagged instances are already stopped")
        return []

    results = []
    for db_id in db_identifiers:
        try:
            rds_client.stop_db_instance(DBInstanceIdentifier=db_id)
            logger.info("RDS stop: %s - SUCCESS", db_id)
            results.append({"id": db_id, "status": "success"})
        except Exception as e:
            logger.error("RDS stop: %s - FAILED: %s", db_id, str(e))
            results.append({"id": db_id, "status": "failed", "error": str(e)})
    return results


def lambda_handler(event, context):
    logger.info("RDS Always-Stop Enforcer triggered")

    rds_client = boto3.client("rds")

    running_instances = get_running_tagged_rds_instances(rds_client)
    logger.info("Found %d RDS instance(s) tagged %s=%s in 'available' state",
                len(running_instances), TAG_KEY, TAG_VALUE)

    results = stop_rds_instances(rds_client, running_instances)

    summary = {"enforcer": "rds-always-stop", "stopped": results}
    logger.info("Summary: %s", json.dumps(summary))

    return {"statusCode": 200, "body": json.dumps(summary)}
