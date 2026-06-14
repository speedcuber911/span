# infra — CloudFormation Infrastructure

Single-EC2 AWS deployment for Project Span. India-only; all resources in `ap-south-1` (Mumbai).

## Architecture

One EC2 instance (`t3.small` to start, upgrade to `t3.medium` when load justifies) running
Amazon Linux 2023. The instance hosts:
- The Span Node.js API + worker (two processes, same box)
- PostgreSQL (co-located initially; migrate to a separate RDS-Postgres instance — NOT Aurora —
  when volume/reliability requires it)

Pay-per-use AWS services (not in the CloudFormation template — provisioned separately or
referenced by ARN):
- **SQS FIFO + DLQ** — parse/analyze job queue
- **S3** (ap-south-1, SSE-KMS) — raw artifact storage
- **KMS** — encryption key for S3 SSE and application-level crypto
- **DynamoDB** — `apple_sub → region` directory table (single-region, India-only at launch)
- **Lambda** (optional glue) — S3-event → SQS enqueue, light cron triggers

## CloudFormation template

`span-infra.yaml` — **being authored separately; do not edit here yet.**

The template will provision:
- VPC + subnets (ap-south-1a/b), security groups
- EC2 instance (AL2023, t3.small) with IAM instance profile
- IAM role: S3 get/put on artifact bucket, SQS send/receive on job queue, KMS decrypt, SSM access
- Elastic IP
- CloudWatch log groups
- (Optional) RDS PostgreSQL single-AZ when Postgres splits off the EC2

## Deploy / Teardown

```bash
# Deploy (uses your personal AWS profile, ap-south-1)
aws cloudformation deploy \
  --template-file span-infra.yaml \
  --stack-name span-india \
  --region ap-south-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile <your-profile>

# Check stack status
aws cloudformation describe-stacks \
  --stack-name span-india \
  --region ap-south-1 \
  --profile <your-profile>

# Teardown
aws cloudformation delete-stack \
  --stack-name span-india \
  --region ap-south-1 \
  --profile <your-profile>
```

## Cost model

- 1x t3.small EC2 (~$15–20/month on-demand; use Reserved for ~60% savings)
- S3 / SQS / KMS / DynamoDB: ~$0 at rest, pay-per-use
- No Aurora, no Fargate line items
- Vertex AI (Gemini + Document AI) + Sarvam: pay-per-call

See `SPAN_MASTER_PLAN.md` §1.2 for the full infrastructure rationale.
