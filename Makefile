.DEFAULT_TARGET: help

# Import settings and constants
include .env

SHELL:=/bin/bash

# CONSTANTS

SOLC_VERSION := $(shell cat foundry.toml | grep solc | cut -d= -f2 | xargs echo || echo "0.8.28")
DEPLOY_SCRIPT := script/Deploy.s.sol:DeployScript
SUPPORTED_VERIFIERS := etherscan blockscout sourcify routescan-mainnet routescan-testnet
MAKE_TEST_TREE_CMD := deno run ./test/scripts/make-test-tree.ts
TEST_TREE_MARKDOWN := TESTS.md
ARTIFACTS_FOLDER := ./artifacts
LOGS_FOLDER := ./logs
VERBOSITY := -vvv

NETWORK_NAME:=$(strip $(subst ',, $(subst ",,$(NETWORK_NAME))))
CHAIN_ID:=$(strip $(subst ',, $(subst ",,$(CHAIN_ID))))
VERIFIER:=$(strip $(subst ',, $(subst ",,$(VERIFIER))))

TEST_COVERAGE_SRC_FILES := $(wildcard test/*.sol test/**/*.sol src/*.sol src/**/*.sol)
TEST_SOURCE_FILES := $(wildcard test/*.t.yaml test/integration/*.t.yaml)
TEST_TREE_FILES := $(TEST_SOURCE_FILES:.t.yaml=.tree)
DEPLOYMENT_ADDRESS := $(shell cast wallet address --private-key $(DEPLOYMENT_PRIVATE_KEY) 2>/dev/null || echo "NOTE: DEPLOYMENT_PRIVATE_KEY is not properly set on .env" > /dev/stderr)
MULTISIG_MEMBERS_FILE := ./multisig-members.json

DEPLOYMENT_LOG_FILE=deployment-$(NETWORK_NAME)-$(shell date +"%y-%m-%d-%H-%M").log

# Check values

ifeq ($(filter $(VERIFIER),$(SUPPORTED_VERIFIERS)),)
  $(error Unknown verifier: $(VERIFIER). It must be one of: $(SUPPORTED_VERIFIERS))
endif

# Conditional assignments

ifeq ($(VERIFIER), etherscan)
	# VERIFIER_URL := https://api.etherscan.io/api
	VERIFIER_API_KEY := $(ETHERSCAN_API_KEY)
	VERIFIER_PARAMS := --verifier $(VERIFIER) --etherscan-api-key $(ETHERSCAN_API_KEY)
endif

ifeq ($(VERIFIER), blockscout)
	VERIFIER_URL := https://$(BLOCKSCOUT_HOST_NAME)/api\?
	VERIFIER_API_KEY := ""
	VERIFIER_PARAMS = --verifier $(VERIFIER) --verifier-url "$(VERIFIER_URL)"
endif

ifeq ($(VERIFIER), sourcify)
endif

ifneq ($(filter $(VERIFIER), routescan-mainnet routescan-testnet),)
	ifeq ($(VERIFIER), routescan-mainnet)
		VERIFIER_URL := https://api.routescan.io/v2/network/mainnet/evm/$(CHAIN_ID)/etherscan
	else
		VERIFIER_URL := https://api.routescan.io/v2/network/testnet/evm/$(CHAIN_ID)/etherscan
	endif

	VERIFIER := custom
	VERIFIER_API_KEY := "verifyContract"
	VERIFIER_PARAMS = --verifier $(VERIFIER) --verifier-url '$(VERIFIER_URL)' --etherscan-api-key $(VERIFIER_API_KEY)
endif

# When invoked like `make deploy slow=true`
ifeq ($(slow),true)
	SLOW_FLAG := --slow
endif

# TARGETS

.PHONY: help
help: ## Display the available targets
	@echo -e "Available targets:\n"
	@cat Makefile | while IFS= read -r line; do \
	   if [[ "$$line" == "##" ]]; then \
			echo "" ; \
		elif [[ "$$line" =~ ^##\ (.*)$$ ]]; then \
			printf "\n$${BASH_REMATCH[1]}\n\n" ; \
		elif [[ "$$line" =~ ^([^:]+):(.*)##\ (.*)$$ ]]; then \
			printf "%s %-*s %s\n" "- make" 18 "$${BASH_REMATCH[1]}" "$${BASH_REMATCH[3]}" ; \
		fi ; \
	done

##

.PHONY: init
init: $(MULTISIG_MEMBERS_FILE) ## Check the dependencies and prompt to install if needed
	@which deno > /dev/null && echo "Deno is available" || echo "Install Deno:  curl -fsSL https://deno.land/install.sh | sh"
	@which bulloak > /dev/null && echo "bulloak is available" || echo "Install bulloak:  cargo install bulloak"

	@which forge > /dev/null || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

.PHONY: clean
clean: ## Clean the build artifacts
	forge clean
	rm -f $(TEST_TREE_FILES)
	rm -f $(TEST_TREE_MARKDOWN)
	rm -Rf ./out/* lcov.info* ./report/*

$(MULTISIG_MEMBERS_FILE):
	@echo "Creating $(@)"
	@echo "NOTE: Edit the correct values of $(@) before you continue"
	@printf '{\n\t"members": []\n}' > $(@)

## Testing lifecycle:

# Run tests faster, locally
test: export ETHERSCAN_API_KEY=

.PHONY: test
test: ## Run unit tests, locally
	forge test $(VERBOSITY)

test-coverage: report/index.html ## Generate an HTML coverage report under ./report
	@which open > /dev/null && open report/index.html || true
	@which xdg-open > /dev/null && xdg-open report/index.html || true

report/index.html: lcov.info
	genhtml $^ -o report

lcov.info: $(TEST_COVERAGE_SRC_FILES)
	forge coverage --report lcov

##

sync-tests: $(TEST_TREE_FILES) ## Scaffold or sync tree files into solidity tests
	@for file in $^; do \
		if [ ! -f $${file%.tree}.t.sol ]; then \
			echo "[Scaffold]   $${file%.tree}.t.sol" ; \
			bulloak scaffold -s $(SOLC_VERSION) --vm-skip -w $$file ; \
		else \
			echo "[Sync file]  $${file%.tree}.t.sol" ; \
			bulloak check --fix $$file ; \
		fi \
	done

check-tests: $(TEST_TREE_FILES) ## Checks if solidity files are out of sync
	bulloak check $^

markdown-tests: $(TEST_TREE_MARKDOWN) ## Generates a markdown file with the test definitions rendered as a tree

# Generate single a markdown file with the test trees
$(TEST_TREE_MARKDOWN): $(TEST_TREE_FILES)
	@echo "[Markdown]   $(@)"
	@echo "# Test tree definitions" > $@
	@echo "" >> $@
	@echo "Below is the graphical definition of the contract tests implemented on [the test folder](./test)" >> $@
	@echo "" >> $@

	@for file in $^; do \
		echo "\`\`\`" >> $@ ; \
		cat $$file >> $@ ; \
		echo "\`\`\`" >> $@ ; \
		echo "" >> $@ ; \
	done

# Internal dependencies and transformations

$(TEST_TREE_FILES): $(TEST_SOURCE_FILES)

%.tree: %.t.yaml
	@for file in $^; do \
	  echo "[Convert]    $$file -> $${file%.t.yaml}.tree" ; \
		cat $$file | $(MAKE_TEST_TREE_CMD) > $${file%.t.yaml}.tree ; \
	done

## Deployment targets:

predeploy: export SIMULATE=true

.PHONY: predeploy
predeploy: ## Simulate a protocol deployment
	@echo "Simulating the deployment"
	forge script $(DEPLOY_SCRIPT) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

.PHONY: deploy
deploy: test ## Deploy the protocol, verify the code and write to ./artifacts
	@echo "Starting the deployment"
	@mkdir -p $(LOGS_FOLDER) $(ARTIFACTS_FOLDER)
	forge script $(DEPLOY_SCRIPT) \
		--rpc-url $(RPC_URL) \
		--retries 10 \
		--delay 8 \
		--broadcast \
		$(SLOW_FLAG) \
		--verify \
		$(VERIFIER_PARAMS) \
		$(VERBOSITY) 2>&1 | tee -a $(LOGS_FOLDER)/$(DEPLOYMENT_LOG_FILE)

.PHONY: resume
resume: test ## Retry the last deployment transactions, verify the code and write to ./artifacts
	@echo "Retrying the deployment"
	@mkdir -p $(LOGS_FOLDER) $(ARTIFACTS_FOLDER)
	forge script $(DEPLOY_SCRIPT) \
		--rpc-url $(RPC_URL) \
		--retries 10 \
		--delay 8 \
		--broadcast \
		$(SLOW_FLAG) \
		--verify \
		--resume \
		$(VERIFIER_PARAMS) \
		$(VERBOSITY) 2>&1 | tee -a $(LOGS_FOLDER)/$(DEPLOYMENT_LOG_FILE)

## Verification:

.PHONY: verify-etherscan
verify-etherscan: broadcast/Deploy.s.sol/$(CHAIN_ID)/run-latest.json ## Verify the last deployment on an Etherscan compatible explorer
	forge build
	bash script/verify-contracts.sh $(CHAIN_ID) $(VERIFIER) $(VERIFIER_URL) $(VERIFIER_API_KEY)

.PHONY: verify-blockscout
verify-blockscout: broadcast/Deploy.s.sol/$(CHAIN_ID)/run-latest.json ## Verify the last deployment on BlockScout
	forge build
	bash script/verify-contracts.sh $(CHAIN_ID) $(VERIFIER) https://$(BLOCKSCOUT_HOST_NAME)/api $(VERIFIER_API_KEY)

.PHONY: verify-sourcify
verify-sourcify: broadcast/Deploy.s.sol/$(CHAIN_ID)/run-latest.json ## Verify the last deployment on Sourcify
	forge build
	bash script/verify-contracts.sh $(CHAIN_ID) $(VERIFIER) "" ""

##

.PHONY: refund
refund: ## Refund the remaining balance left on the deployment account
	@echo "Refunding the remaining balance on $(DEPLOYMENT_ADDRESS)"
	@if [ -z $(REFUND_ADDRESS) -o $(REFUND_ADDRESS) = "0x0000000000000000000000000000000000000000" ]; then \
		echo "- The refund address is empty" ; \
		exit 1; \
	fi
	@BALANCE=$(shell cast balance $(DEPLOYMENT_ADDRESS) --rpc-url $(RPC_URL)) && \
		GAS_PRICE=$(shell cast gas-price --rpc-url $(RPC_URL)) && \
		REMAINING=$$(echo "$$BALANCE - $$GAS_PRICE * 21000" | bc) && \
		\
		ENOUGH_BALANCE=$$(echo "$$REMAINING > 0" | bc) && \
		if [ "$$ENOUGH_BALANCE" = "0" ]; then \
			echo -e "- No balance can be refunded: $$BALANCE wei\n- Minimum balance: $${REMAINING:1} wei" ; \
			exit 1; \
		fi ; \
		echo -n -e "Summary:\n- Refunding: $$REMAINING (wei)\n- Recipient: $(REFUND_ADDRESS)\n\nContinue? (y/N) " && \
		\
		read CONFIRM && \
		if [ "$$CONFIRM" != "y" ]; then echo "Aborting" ; exit 1; fi ; \
		\
		cast send --private-key $(DEPLOYMENT_PRIVATE_KEY) \
			--rpc-url $(RPC_URL) \
			--value $$REMAINING \
			$(REFUND_ADDRESS)

# Troubleshooting and helpers

.PHONY: gas-price
gas-price:
	cast gas-price --rpc-url $(RPC_URL)

.PHONY: clean-nonces
clean-nonces:
	for nonce in $(nonces); do \
	  make clean-nonce nonce=$$nonce ; \
	done

.PHONY: clean-nonce
clean-nonce:
	cast send --private-key $(DEPLOYMENT_PRIVATE_KEY) \
 			--rpc-url $(RPC_URL) \
 			--value 0 \
      --nonce $(nonce) \
 			$(DEPLOYMENT_ADDRESS)
