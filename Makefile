# Cloud Launchpad — common tasks
#
# Every target is a thin wrapper around a script or a single command, so you can
# always run the underlying tool directly. Nothing here is required: if `make`
# is not installed, use the commands shown in each recipe.

.DEFAULT_GOAL := help
.PHONY: help serve build test clean deploy invalidate verify tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy tf-output

help: ## Show the available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

serve: ## Preview the site on http://localhost:8080
	./scripts/serve.sh

build: ## Assemble the deployable site into dist/
	./scripts/build.sh

test: ## Run the static site checks
	./scripts/test.sh

clean: ## Remove build output
	rm -rf dist

# --- Deployment ------------------------------------------------------------
# These read their configuration from Terraform outputs, so there is nothing
# to copy by hand and nothing to get out of step.

deploy: build ## Build and upload the site to S3
	S3_BUCKET=$$(cd infra && terraform output -raw bucket_name) ./scripts/deploy.sh

invalidate: ## Clear the CloudFront cache
	CLOUDFRONT_DISTRIBUTION_ID=$$(cd infra && terraform output -raw cloudfront_distribution_id) \
		WAIT=1 ./scripts/invalidate.sh

verify: ## Check the live site
	SITE_URL=$$(cd infra && terraform output -raw site_url) \
		S3_BUCKET=$$(cd infra && terraform output -raw bucket_name) \
		AWS_REGION=$$(cd infra && terraform output -raw aws_region) \
		./scripts/verify-deployment.sh

# --- Terraform -------------------------------------------------------------

tf-init: ## Initialise Terraform
	cd infra && terraform init

tf-fmt: ## Format Terraform files
	cd infra && terraform fmt -recursive

tf-validate: ## Validate the Terraform configuration
	cd infra && terraform validate

tf-plan: ## Show what Terraform would change
	cd infra && terraform plan

tf-apply: ## Apply the Terraform configuration
	cd infra && terraform apply

tf-output: ## Show the Terraform outputs
	cd infra && terraform output

tf-destroy: ## Destroy all infrastructure created by this project
	cd infra && terraform destroy
