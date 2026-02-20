#!/usr/bin/env bash
# deploy.sh - Deploy EC2 & RDS Auto-Scheduler via AWS CloudShell
# Creates: IAM Role, Lambda Function, EventBridge Rules
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="ec2-rds-auto-scheduler"
ROLE_NAME="ec2-rds-auto-scheduler-role"
POLICY_NAME="ec2-rds-auto-scheduler-policy"

# Schedule: 9 AM CST (15:00 UTC) start, 9 PM CST (03:00 UTC next day) stop
# Weekdays only. CST = UTC-6 (fixed; adjust if you observe CDT/UTC-5).
START_CRON="cron(0 15 ? * MON-FRI *)"
STOP_CRON="cron(0 3 ? * TUE-SAT *)"

START_RULE_NAME="${FUNCTION_NAME}-start"
STOP_RULE_NAME="${FUNCTION_NAME}-stop"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="${SCRIPT_DIR}/lambda_function"
ZIP_FILE="/tmp/${FUNCTION_NAME}.zip"

echo "============================================"
echo " EC2 & RDS Auto-Scheduler - Deployment"
echo "============================================"
echo "Region:        ${REGION}"
echo "Function:      ${FUNCTION_NAME}"
echo "IAM Role:      ${ROLE_NAME}"
echo "Start:         9 AM CST (Mon-Fri)"
echo "Stop:          9 PM CST (Mon-Fri)"
echo "Tag:           AutoSchedule = true"
echo "============================================"
echo ""

# ─── 1. Create IAM Role ─────────────────────────────────────────────────────
echo "[1/6] Creating IAM role: ${ROLE_NAME}..."

ASSUME_ROLE_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Create role (ignore error if it already exists)
if aws iam get-role --role-name "${ROLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "       Role already exists, skipping creation."
else
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "${ASSUME_ROLE_POLICY}" \
        --region "${REGION}" \
        --output text --query 'Role.Arn' >/dev/null
    echo "       Role created."
fi

ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --region "${REGION}" \
    --output text --query 'Role.Arn')
echo "       Role ARN: ${ROLE_ARN}"

# ─── 2. Attach Inline Policy ────────────────────────────────────────────────
echo "[2/6] Attaching inline policy: ${POLICY_NAME}..."

INLINE_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StartInstances",
        "ec2:StopInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:ListTagsForResource",
        "rds:StartDBInstance",
        "rds:StopDBInstance"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}'

aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "${POLICY_NAME}" \
    --policy-document "${INLINE_POLICY}" \
    --region "${REGION}"
echo "       Policy attached."

# Wait for IAM role propagation
echo "       Waiting 10s for IAM role propagation..."
sleep 10

# ─── 3. Package Lambda Function ─────────────────────────────────────────────
echo "[3/6] Packaging Lambda function..."

if [ ! -f "${LAMBDA_DIR}/index.py" ]; then
    echo "ERROR: ${LAMBDA_DIR}/index.py not found."
    exit 1
fi

rm -f "${ZIP_FILE}"
(cd "${LAMBDA_DIR}" && zip -q "${ZIP_FILE}" index.py)
echo "       Packaged: ${ZIP_FILE}"

# ─── 4. Create or Update Lambda Function ─────────────────────────────────────
echo "[4/6] Deploying Lambda function: ${FUNCTION_NAME}..."

if aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "       Function exists, updating code..."
    aws lambda update-function-code \
        --function-name "${FUNCTION_NAME}" \
        --zip-file "fileb://${ZIP_FILE}" \
        --region "${REGION}" \
        --output text --query 'FunctionArn' >/dev/null
    echo "       Function code updated."
else
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.12 \
        --role "${ROLE_ARN}" \
        --handler index.lambda_handler \
        --zip-file "fileb://${ZIP_FILE}" \
        --timeout 120 \
        --memory-size 128 \
        --region "${REGION}" \
        --output text --query 'FunctionArn' >/dev/null
    echo "       Function created."
fi

LAMBDA_ARN=$(aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" \
    --output text --query 'Configuration.FunctionArn')
echo "       Lambda ARN: ${LAMBDA_ARN}"

# ─── 5. Create EventBridge Rules ─────────────────────────────────────────────
echo "[5/6] Creating EventBridge rules..."

# Start rule
aws events put-rule \
    --name "${START_RULE_NAME}" \
    --schedule-expression "${START_CRON}" \
    --state ENABLED \
    --description "Start EC2/RDS instances at 9 AM CST (Mon-Fri)" \
    --region "${REGION}" \
    --output text --query 'RuleArn' >/dev/null
echo "       Start rule created: ${START_RULE_NAME}"

# Stop rule
aws events put-rule \
    --name "${STOP_RULE_NAME}" \
    --schedule-expression "${STOP_CRON}" \
    --state ENABLED \
    --description "Stop EC2/RDS instances at 9 PM CST (Mon-Fri)" \
    --region "${REGION}" \
    --output text --query 'RuleArn' >/dev/null
echo "       Stop rule created: ${STOP_RULE_NAME}"

# ─── 6. Wire EventBridge -> Lambda ──────────────────────────────────────────
echo "[6/6] Adding Lambda targets and permissions..."

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id "AllowEventBridgeStart" \
    --action "lambda:InvokeFunction" \
    --principal "events.amazonaws.com" \
    --source-arn "$(aws events describe-rule --name "${START_RULE_NAME}" --region "${REGION}" --output text --query 'Arn')" \
    --region "${REGION}" >/dev/null 2>&1 || echo "       Start permission already exists."

aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id "AllowEventBridgeStop" \
    --action "lambda:InvokeFunction" \
    --principal "events.amazonaws.com" \
    --source-arn "$(aws events describe-rule --name "${STOP_RULE_NAME}" --region "${REGION}" --output text --query 'Arn')" \
    --region "${REGION}" >/dev/null 2>&1 || echo "       Stop permission already exists."

# Add Lambda as target for each rule
aws events put-targets \
    --rule "${START_RULE_NAME}" \
    --targets "Id=1,Arn=${LAMBDA_ARN},Input={\"action\":\"start\"}" \
    --region "${REGION}" >/dev/null
echo "       Start target added."

aws events put-targets \
    --rule "${STOP_RULE_NAME}" \
    --targets "Id=1,Arn=${LAMBDA_ARN},Input={\"action\":\"stop\"}" \
    --region "${REGION}" >/dev/null
echo "       Stop target added."

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo " Deployment Complete!"
echo "============================================"
echo ""
echo "Resources created:"
echo "  IAM Role:          ${ROLE_NAME}"
echo "  Lambda Function:   ${FUNCTION_NAME}"
echo "  Start Rule:        ${START_RULE_NAME}  (${START_CRON})"
echo "  Stop Rule:         ${STOP_RULE_NAME}   (${STOP_CRON})"
echo ""
echo "Next steps:"
echo "  1. Tag your EC2 instances:  AutoSchedule = true"
echo "  2. Tag your RDS instances:  AutoSchedule = true"
echo "  3. Verify in the AWS Console under EventBridge > Rules"
echo ""
echo "To remove all resources, run: bash teardown.sh"
echo "============================================"
