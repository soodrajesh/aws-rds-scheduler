# EC2 & RDS Auto-Scheduler

Automatically start and stop EC2 and RDS instances on a schedule using AWS Lambda and EventBridge. Deploy everything from **AWS CloudShell** with a single bash script.

## How It Works

1. **Tag your resources** with `AutoSchedule = true`
2. **Run `deploy.sh`** from AWS CloudShell
3. EventBridge triggers a Lambda function on a cron schedule:
   - **Start** at 9:00 AM CST (Mon-Fri)
   - **Stop** at 9:00 PM CST (Mon-Fri)
4. The Lambda discovers all tagged EC2 and RDS instances and starts/stops them

```
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────────┐
│  EventBridge     │       │  Lambda Function  │       │  EC2 / RDS Instances │
│                  │       │                   │       │                      │
│  Start: 9AM CST  ├──────►│  Discover tagged  ├──────►│  AutoSchedule=true   │
│  Stop:  9PM CST  │       │  resources &      │       │                      │
│  (Mon-Fri)       │       │  start/stop them  │       │                      │
└──────────────────┘       └──────────────────┘       └──────────────────────┘
```

## Prerequisites

- AWS CLI configured (CloudShell has this by default)
- IAM permissions to create: Lambda functions, IAM roles/policies, EventBridge rules
- `zip` utility (available in CloudShell)

## Quick Start

### 1. Deploy

```bash
# Clone or upload this folder to CloudShell, then:
cd aws-rds-scheduler
bash deploy.sh
```

The script will create:
- IAM Role: `ec2-rds-auto-scheduler-role`
- Lambda Function: `ec2-rds-auto-scheduler`
- EventBridge Start Rule: `ec2-rds-auto-scheduler-start`
- EventBridge Stop Rule: `ec2-rds-auto-scheduler-stop`

### 2. Tag Your Resources

Add the following tag to any EC2 or RDS instance you want scheduled:

| Tag Key        | Tag Value |
|----------------|-----------|
| `AutoSchedule` | `true`    |

**EC2 (AWS Console):**
EC2 > Instances > Select instance > Tags > Manage tags > Add tag

**EC2 (CLI):**
```bash
aws ec2 create-tags --resources i-0123456789abcdef0 --tags Key=AutoSchedule,Value=true
```

**RDS (AWS Console):**
RDS > Databases > Select DB > Tags > Add tag

**RDS (CLI):**
```bash
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:db:my-database \
    --tags Key=AutoSchedule,Value=true
```

### 3. Verify

- Check **EventBridge > Rules** in the AWS Console to see the two scheduled rules
- Check **Lambda > Functions > ec2-rds-auto-scheduler** to see the function
- Check **CloudWatch Logs** after the first trigger to verify execution

### 4. Teardown

To remove all created resources:

```bash
bash teardown.sh
```

## Schedule Details

| Action | CST Time           | UTC Time           | Days     |
|--------|--------------------|--------------------| ---------|
| Start  | 9:00 AM CST        | 3:00 PM (15:00) UTC | Mon-Fri  |
| Stop   | 9:00 PM CST        | 3:00 AM (03:00) UTC | Tue-Sat* |

*The stop rule fires Tue-Sat in UTC because 9 PM CST Monday = 3 AM UTC Tuesday.

### Daylight Saving Time (CDT) Note

The schedule uses **CST (UTC-6)** as a fixed offset. During Central Daylight Time (CDT, UTC-5, typically Mar-Nov), the effective local times shift by one hour:
- Start becomes **10:00 AM CDT**
- Stop becomes **10:00 PM CDT**

To adjust for CDT, update the cron expressions in `deploy.sh`:
- Start: `cron(0 14 ? * MON-FRI *)` (9 AM CDT = 14:00 UTC)
- Stop: `cron(0 2 ? * TUE-SAT *)` (9 PM CDT = 02:00 UTC)

## Configuration

Edit the variables at the top of `deploy.sh` and `teardown.sh` to customise:

| Variable         | Default                        | Description                    |
|------------------|--------------------------------|--------------------------------|
| `REGION`         | `us-east-1`                    | AWS region                     |
| `FUNCTION_NAME`  | `ec2-rds-auto-scheduler`       | Lambda function name           |
| `ROLE_NAME`      | `ec2-rds-auto-scheduler-role`  | IAM role name                  |
| `START_CRON`     | `cron(0 15 ? * MON-FRI *)`    | Start schedule (UTC)           |
| `STOP_CRON`      | `cron(0 3 ? * TUE-SAT *)`     | Stop schedule (UTC)            |

## Supported Resources

| Service | Supported          | Notes                                                    |
|---------|--------------------|----------------------------------------------------------|
| EC2     | Yes                | Standard instances (not Spot)                            |
| RDS     | Yes                | Standard DB instances                                    |
| Aurora  | No (not yet)       | Aurora uses `start-db-cluster` / `stop-db-cluster` APIs  |

## Project Structure

```
aws-rds-scheduler/
├── deploy.sh              # CloudShell deployment script
├── teardown.sh            # CloudShell teardown script
├── lambda_function/
│   └── index.py           # Lambda handler (Python 3.12)
├── README.md
└── .gitignore
```

## Troubleshooting

- **Lambda not triggering?** Check EventBridge rules are ENABLED in the console.
- **Instances not starting/stopping?** Verify the `AutoSchedule = true` tag is set (case-sensitive). Check CloudWatch Logs for the Lambda function.
- **Permission errors?** Ensure the IAM role has the correct inline policy. Re-run `deploy.sh` to reapply.
- **Wrong timezone?** See the CDT note above. Adjust cron expressions in `deploy.sh`.

## Created

February 20, 2026
