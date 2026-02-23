#!/usr/bin/env bash
# deploy-rds-enforcer.sh - Deploy RDS Always-Stop Enforcer via AWS CloudShell
# Creates: Lambda Function, EventBridge Rule (reuses existing IAM role)
#
# AWS auto-restarts stopped RDS instances after 7 days. This Lambda runs every
# 6 hours and stops any RDS instance tagged AlwaysStopRDS=true that is running.
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
# On CloudShell: credentials are automatic, no profile needed.
# For local testing: AWS_PROFILE=ce-dev bash deploy-rds-enforcer.sh
if [ -n "${AWS_PROFILE:-}" ]; then
    export AWS_PROFILE
fi
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="rds-always-stop-enforcer"
RULE_NAME="${FUNCTION_NAME}-rule"

# Reuse the IAM role from the main ec2-rds scheduler
ROLE_NAME="ec2-rds-auto-scheduler-role"

SCHEDULE="rate(6 hours)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="${SCRIPT_DIR}/rds_enforcer"
ZIP_FILE="/tmp/${FUNCTION_NAME}.zip"

echo "============================================"
echo " RDS Always-Stop Enforcer - Deployment"
echo "============================================"
echo "Profile:       ${AWS_PROFILE:-<default/CloudShell>}"
echo "Region:        ${REGION}"
echo "Function:      ${FUNCTION_NAME}"
echo "IAM Role:      ${ROLE_NAME} (shared)"
echo "Schedule:      ${SCHEDULE}"
echo "Tag:           AlwaysStopRDS = true"
echo "============================================"
echo ""

# ─── 1. Verify IAM Role Exists ──────────────────────────────────────────────
echo "[1/4] Verifying IAM role: ${ROLE_NAME}..."

if ! aws iam get-role --role-name "${ROLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "ERROR: IAM role '${ROLE_NAME}' not found."
    echo "       Run 'bash deploy.sh' first to create the main scheduler (which creates the role)."
    exit 1
fi

ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --region "${REGION}" \
    --output text --query 'Role.Arn')
echo "       Role ARN: ${ROLE_ARN}"

# ─── 2. Package Lambda Function ─────────────────────────────────────────────
echo "[2/4] Packaging Lambda function..."

if [ ! -f "${LAMBDA_DIR}/index.py" ]; then
    echo "ERROR: ${LAMBDA_DIR}/index.py not found."
    exit 1
fi

rm -f "${ZIP_FILE}"
(cd "${LAMBDA_DIR}" && zip -q "${ZIP_FILE}" index.py)
echo "       Packaged: ${ZIP_FILE}"

# ─── 3. Create or Update Lambda Function ─────────────────────────────────────
echo "[3/4] Deploying Lambda function: ${FUNCTION_NAME}..."

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

# ─── 4. Create EventBridge Rule + Target ─────────────────────────────────────
echo "[4/4] Creating EventBridge rule and wiring target..."

aws events put-rule \
    --name "${RULE_NAME}" \
    --schedule-expression "${SCHEDULE}" \
    --state ENABLED \
    --description "Every 6 hours: stop RDS instances tagged AlwaysStopRDS=true" \
    --region "${REGION}" \
    --output text --query 'RuleArn' >/dev/null
echo "       Rule created: ${RULE_NAME}"

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id "AllowEventBridgeEnforcer" \
    --action "lambda:InvokeFunction" \
    --principal "events.amazonaws.com" \
    --source-arn "$(aws events describe-rule --name "${RULE_NAME}" --region "${REGION}" --output text --query 'Arn')" \
    --region "${REGION}" >/dev/null 2>&1 || echo "       Permission already exists."

# Add Lambda as target
aws events put-targets \
    --rule "${RULE_NAME}" \
    --targets '[{"Id":"1","Arn":"'"${LAMBDA_ARN}"'"}]' \
    --region "${REGION}" >/dev/null
echo "       Target added."

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo " Deployment Complete!"
echo "============================================"
echo ""
echo "Resources created:"
echo "  Lambda Function:   ${FUNCTION_NAME}"
echo "  EventBridge Rule:  ${RULE_NAME}  (${SCHEDULE})"
echo "  IAM Role:          ${ROLE_NAME} (shared, already existed)"
echo ""
echo "Next steps:"
echo "  Tag your RDS instances:  AlwaysStopRDS = true"
echo ""
echo "To remove, run: bash teardown-rds-enforcer.sh"
echo "============================================"
