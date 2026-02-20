#!/usr/bin/env bash
# teardown.sh - Remove all EC2 & RDS Auto-Scheduler resources
# Safe to run multiple times (idempotent).
set -euo pipefail

# ─── Configuration (must match deploy.sh) ────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="ec2-rds-auto-scheduler"
ROLE_NAME="ec2-rds-auto-scheduler-role"
POLICY_NAME="ec2-rds-auto-scheduler-policy"
START_RULE_NAME="${FUNCTION_NAME}-start"
STOP_RULE_NAME="${FUNCTION_NAME}-stop"

echo "============================================"
echo " EC2 & RDS Auto-Scheduler - Teardown"
echo "============================================"
echo "Region:   ${REGION}"
echo "============================================"
echo ""

# ─── 1. Remove EventBridge Targets ──────────────────────────────────────────
echo "[1/5] Removing EventBridge targets..."

aws events remove-targets --rule "${START_RULE_NAME}" --ids "1" --region "${REGION}" 2>/dev/null \
    && echo "       Removed target from ${START_RULE_NAME}" \
    || echo "       Target for ${START_RULE_NAME} not found (already removed)."

aws events remove-targets --rule "${STOP_RULE_NAME}" --ids "1" --region "${REGION}" 2>/dev/null \
    && echo "       Removed target from ${STOP_RULE_NAME}" \
    || echo "       Target for ${STOP_RULE_NAME} not found (already removed)."

# ─── 2. Delete EventBridge Rules ────────────────────────────────────────────
echo "[2/5] Deleting EventBridge rules..."

aws events delete-rule --name "${START_RULE_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "       Deleted rule: ${START_RULE_NAME}" \
    || echo "       Rule ${START_RULE_NAME} not found (already deleted)."

aws events delete-rule --name "${STOP_RULE_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "       Deleted rule: ${STOP_RULE_NAME}" \
    || echo "       Rule ${STOP_RULE_NAME} not found (already deleted)."

# ─── 3. Delete Lambda Function ──────────────────────────────────────────────
echo "[3/5] Deleting Lambda function: ${FUNCTION_NAME}..."

aws lambda delete-function --function-name "${FUNCTION_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "       Deleted Lambda function." \
    || echo "       Lambda function not found (already deleted)."

# ─── 4. Delete IAM Inline Policy ────────────────────────────────────────────
echo "[4/5] Removing IAM inline policy: ${POLICY_NAME}..."

aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${POLICY_NAME}" 2>/dev/null \
    && echo "       Deleted inline policy." \
    || echo "       Inline policy not found (already deleted)."

# ─── 5. Delete IAM Role ─────────────────────────────────────────────────────
echo "[5/5] Deleting IAM role: ${ROLE_NAME}..."

aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null \
    && echo "       Deleted IAM role." \
    || echo "       IAM role not found (already deleted)."

echo ""
echo "============================================"
echo " Teardown Complete!"
echo "============================================"
echo "All scheduler resources have been removed."
echo "============================================"
