#!/usr/bin/env bash
# teardown-rds-enforcer.sh - Remove RDS Always-Stop Enforcer resources
# Does NOT remove the shared IAM role (belongs to the main scheduler).
# Safe to run multiple times (idempotent).
set -euo pipefail

# ─── Configuration (must match deploy-rds-enforcer.sh) ──────────────────────
# On CloudShell: credentials are automatic, no profile needed.
# For local testing: AWS_PROFILE=ce-dev bash teardown-rds-enforcer.sh
if [ -n "${AWS_PROFILE:-}" ]; then
    export AWS_PROFILE
fi
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="rds-always-stop-enforcer"
RULE_NAME="${FUNCTION_NAME}-rule"

echo "============================================"
echo " RDS Always-Stop Enforcer - Teardown"
echo "============================================"
echo "Region:   ${REGION}"
echo "============================================"
echo ""

# ─── 1. Remove EventBridge Target ───────────────────────────────────────────
echo "[1/3] Removing EventBridge target..."

aws events remove-targets --rule "${RULE_NAME}" --ids "1" --region "${REGION}" 2>/dev/null \
    && echo "       Removed target from ${RULE_NAME}" \
    || echo "       Target not found (already removed)."

# ─── 2. Delete EventBridge Rule ─────────────────────────────────────────────
echo "[2/3] Deleting EventBridge rule: ${RULE_NAME}..."

aws events delete-rule --name "${RULE_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "       Deleted rule." \
    || echo "       Rule not found (already deleted)."

# ─── 3. Delete Lambda Function ──────────────────────────────────────────────
echo "[3/3] Deleting Lambda function: ${FUNCTION_NAME}..."

aws lambda delete-function --function-name "${FUNCTION_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "       Deleted Lambda function." \
    || echo "       Lambda function not found (already deleted)."

echo ""
echo "============================================"
echo " Teardown Complete!"
echo "============================================"
echo "Enforcer resources removed."
echo "Note: Shared IAM role 'ec2-rds-auto-scheduler-role' was NOT deleted."
echo "============================================"
