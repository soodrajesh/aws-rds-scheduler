# AWS EC2 & RDS Scheduler -- Quick Guide

> Two Lambda functions deployed via bash scripts from AWS CloudShell.
> Tag-based -- no hardcoded instance IDs. Just add a tag and you're done.

---

## Lambda 1: EC2 & RDS Auto-Scheduler

**What it does:** Starts tagged EC2 and RDS instances at **9 AM CST** and stops them at **9 PM CST**, Monday through Friday.

**Tag:** `AutoSchedule` = `true`

**AWS Resources Created:**

| Resource | Name |
|---|---|
| IAM Role | `ec2-rds-auto-scheduler-role` |
| Lambda | `ec2-rds-auto-scheduler` |
| EventBridge (start) | `ec2-rds-auto-scheduler-start` -- `cron(0 15 ? * MON-FRI *)` |
| EventBridge (stop) | `ec2-rds-auto-scheduler-stop` -- `cron(0 3 ? * TUE-SAT *)` |

### Deploy

```bash
# CloudShell
bash deploy.sh

# Local (with profile)
AWS_PROFILE=ce-dev bash deploy.sh
```

### Tag resources

**EC2:**
```bash
aws ec2 create-tags --resources i-0123456789abcdef0 \
    --tags Key=AutoSchedule,Value=true
```

**RDS:**
```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:ACCOUNT_ID:db:my-database \
    --tags Key=AutoSchedule,Value=true
```

### Remove

```bash
bash teardown.sh
```

---

## Lambda 2: RDS Always-Stop Enforcer

**What it does:** AWS auto-restarts stopped RDS instances after 7 days. This Lambda runs **every 6 hours, 24/7** and stops any tagged RDS instance that has come back online.

**Tag:** `AlwaysStopRDS` = `true`

**AWS Resources Created:**

| Resource | Name |
|---|---|
| IAM Role | `ec2-rds-auto-scheduler-role` *(shared, not created again)* |
| Lambda | `rds-always-stop-enforcer` |
| EventBridge | `rds-always-stop-enforcer-rule` -- `rate(6 hours)` |

### Deploy

```bash
# Deploy the main scheduler first (creates the shared IAM role)
bash deploy.sh

# Then deploy the enforcer
bash deploy-rds-enforcer.sh
```

### Tag resources

```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:ACCOUNT_ID:db:my-database \
    --tags Key=AlwaysStopRDS,Value=true
```

### Remove

```bash
bash teardown-rds-enforcer.sh
```

---

## Tag Reference

| Tag | Value | Applies To | Effect |
|---|---|---|---|
| `AutoSchedule` | `true` | EC2, RDS | Start 9 AM / Stop 9 PM CST, Mon-Fri |
| `AlwaysStopRDS` | `true` | RDS only | Keep stopped 24/7 (re-stops after AWS 7-day restart) |

Tags are **case-sensitive**. Both tags can be used on the same RDS instance.

---

## Schedule at a Glance

| Lambda | Schedule | Days | Timezone |
|---|---|---|---|
| Auto-Scheduler (start) | 9:00 AM CST (15:00 UTC) | Mon-Fri | CST (UTC-6) |
| Auto-Scheduler (stop) | 9:00 PM CST (03:00 UTC) | Mon-Fri | CST (UTC-6) |
| Always-Stop Enforcer | Every 6 hours | Every day | N/A |

> **CDT Note:** During daylight saving (Mar-Nov), CST times shift +1 hour (start becomes 10 AM CDT, stop becomes 10 PM CDT). Update cron in `deploy.sh` if needed.

---

## Verify in AWS Console

1. **EventBridge > Rules** -- confirm rules are ENABLED
2. **Lambda > Functions** -- confirm both functions exist
3. **CloudWatch > Log Groups** -- check `/aws/lambda/ec2-rds-auto-scheduler` and `/aws/lambda/rds-always-stop-enforcer` after first trigger

---

## Teardown (remove everything)

```bash
bash teardown-rds-enforcer.sh   # Remove enforcer first
bash teardown.sh                # Remove scheduler + shared IAM role
```

Order matters -- teardown the enforcer first since it depends on the shared IAM role.

---

*Last updated: February 23, 2026*
