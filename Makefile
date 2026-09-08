# Cloud Launchpad — common tasks
#
# Every target is a thin wrapper around a script or a single command, so you can
# always run the underlying tool directly. Nothing here is required: if `make`
# is not installed, use the commands shown in each recipe.

.DEFAULT_GOAL := help
.PHONY: help serve test

help: ## Show the available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

serve: ## Preview the site on http://localhost:8080
	./scripts/serve.sh

test: ## Run the static site checks
	./scripts/test.sh
