# Infrastructure

Terraform configuration for the Cloud Launchpad platform: a private S3 bucket, a
CloudFront distribution in front of it, optional TLS for a custom domain, and the
IAM role GitHub Actions assumes to deploy.

## Files

| File | Contents |
| --- | --- |
| `versions.tf` | Terraform and provider version constraints |
| `providers.tf` | The default AWS provider, plus a `us_east_1` alias for ACM |
| `variables.tf` | Every input, with validation and documentation |
| `locals.tf` | Data sources and computed names |
| `outputs.tf` | Values the pipeline and the runbook need |
| `terraform.tfvars.example` | A template for your own `terraform.tfvars` |

Files are split by concern rather than crammed into `main.tf`. Terraform does not
care — it loads every `.tf` file in the directory and builds one dependency graph
from the result — but humans reviewing a pull request do.

## Prerequisites

- Terraform ≥ 1.6
- AWS CLI v2, authenticated as a principal that can create S3, CloudFront, ACM and IAM resources
- Confirm which account you are pointed at before you change anything:

```bash
aws sts get-caller-identity
```

## Usage

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # then edit it

terraform init        # download providers, write the lock file
terraform fmt         # canonical formatting
terraform validate    # syntax and type checking, no AWS calls
terraform plan        # what would change — read this every time
terraform apply       # make it so
```

## State

This configuration uses **local state** — a `terraform.tfstate` file in this
directory. That is the right starting point for learning and the wrong answer for a
team: the file is not shared, not locked, and not backed up, and it contains every
attribute of every resource.

`terraform.tfstate` is git-ignored, and it should stay that way. Moving to a remote
backend is the natural next step once more than one person, or more than one
pipeline, needs to apply.

## Tearing it down

```bash
terraform destroy
```

Everything in this configuration is disposable by design. Destroy it when you are
finished; rebuilding takes one command.
