# Electrify — Terraform Infrastructure

Converted from the original CloudFormation template `electrify-public.yml` (DAT403-RIV2025).

---

## Architecture Overview

| Component | AWS Resource |
|---|---|
| Networking | VPC, 3 public + 3 private subnets, IGW, NAT GW, S3 VPC endpoint |
| Database | Aurora PostgreSQL 17 Serverless v2 cluster + 1 instance |
| IDE | EC2 (m5.large, AL2023) running code-server behind CloudFront |
| API | API Gateway HTTP API (JWT auth via Cognito) → Lambda monolith |
| Auth | Cognito User Pool + Identity Pool |
| Frontend | S3 + CloudFront distribution |
| Secrets | Secrets Manager (DB creds, VSCode password, test user password) |
| Lambda Layers | psycopg2-binary + requests (built at deploy time) |
| Support | Lab support Lambda for bootstrap orchestration |

---

## File Structure

```
electrify-terraform/
├── providers.tf        # Terraform & AWS provider config
├── variables.tf        # Input variables
├── locals.tf           # Local values, regional mappings, random suffix
├── networking.tf       # VPC, subnets, IGW, NAT, route tables, S3 endpoint
├── security_groups.tf  # Client and DB security groups
├── s3.tf               # S3 buckets (data, lab_data, website)
├── secrets.tf          # Secrets Manager secrets + random passwords
├── iam.tf              # All IAM roles and instance profiles
├── rds.tf              # Aurora cluster, parameter group, DB instance
├── ec2_vscode.tf       # EC2 VSCode IDE instance + CloudFront distribution
├── cognito.tf          # Cognito User Pool, Client, Identity Pool
├── api_gateway.tf      # HTTP API, JWT authorizer, stage, routes
├── cloudfront.tf       # Website CloudFront distribution (S3 + API origins)
├── lambda.tf           # All Lambda functions (layer builder, monolith, support, etc.)
└── outputs.tf          # Stack outputs
```

---

## Prerequisites

- Terraform >= 1.6.0
- AWS CLI v2 configured with appropriate credentials
- The `aws` CLI must be available in your `PATH` (used by `local-exec` provisioners)
- The target region must be in the supported regions list (see `locals.tf`)

---

## Usage

### 1. Initialize

```bash
terraform init
```

### 2. Plan

```bash
terraform plan -var="aws_region=us-east-1"
```

### 3. Apply

```bash
terraform apply -var="aws_region=us-east-1"
```

### 4. Retrieve sensitive outputs

```bash
# VSCode password
terraform output -raw vscode_password

# Test user password
terraform output -raw application_user_password
```

---

## Important Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `vscode_user` | `participant` | OS user for VSCode server |
| `home_folder` | `/workshop` | Folder opened in VSCode |
| `dev_server_port` | `9091` | Dev server port |
| `vscode_server_port` | `9090` | VSCode server port |

---

## Notes on Custom Resources → Terraform Equivalents

CloudFormation **Custom Resources** (Lambda-backed) have been translated as follows:

| CFN Custom Resource | Terraform Equivalent |
|---|---|
| `resBuildLambdaLayer` | `terraform_data.build_lambda_layer` (local-exec) |
| `resCopyLambdaCode` | `terraform_data.copy_lambda_code` (local-exec) |
| `resLabSupport` | `terraform_data.lab_support` (local-exec) |
| `resSetUserPassword` | `terraform_data.set_user_password` (local-exec) |
| `SecretPlaintext` / `TestUserPasswordPlaintext` | Passwords resolved directly from `random_password` resources |

> **Note**: The `local-exec` provisioners invoke Lambda functions directly using the AWS CLI. This requires that `terraform apply` be run from a machine with appropriate AWS credentials and the `aws` CLI installed.

---

## Cleanup

```bash
terraform destroy -var="aws_region=us-east-1"
```

> S3 buckets are set to `force_destroy = true`, so they will be emptied and deleted automatically.

---

## License

MIT-0 — same as the original CloudFormation template.
