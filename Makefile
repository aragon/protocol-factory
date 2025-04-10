.DEFAULT_TARGET: help

# Import the .env files and export their values
include .env
include constants.mk

SHELL:=/bin/bash

# CONSTANTS

SOLIDITY_VERSION := 0.8.22
TEST_TREE_MARKDOWN := TEST_TREE.md
MAKEFILE := Makefile
DEPLOY_SCRIPT := script/Deploy.s.sol:Deploy
MAKE_TEST_TREE_CMD := deno run ./test/scripts/make-test-tree.ts
VERBOSITY := -vvv

TEST_COVERAGE_SRC_FILES := $(wildcard test/*.sol test/**/*.sol src/*.sol src/**/*.sol src/libs/ProxyLib.sol)
TEST_SOURCE_FILES := $(wildcard test/*.t.yaml test/integration/*.t.yaml)
TEST_TREE_FILES := $(TEST_SOURCE_FILES:.t.yaml=.tree)
DEPLOYMENT_ADDRESS := $(shell cast wallet address --private-key $(DEPLOYMENT_PRIVATE_KEY))

DEPLOYMENT_LOG_FILE=deployment-$(patsubst "%",%,$(PRODNET_NETWORK))-$(shell date +"%y-%m-%d-%H-%M").log

ifneq ($(filter $(NETWORK), $(ETHERSCAN_NETWORKS)),)
	ETHERSCAN_API_KEY_PARAM := --etherscan-api-key $(ETHERSCAN_API_KEY)
endif

ifneq ($(filter $(NETWORK), $(BLOCKSCOUT_NETWORKS)),)
	VERIFIER_TYPE_PARAM = --verifier blockscout
	VERIFIER_URL_PARAM = --verifier-url "https://$(BLOCKSCOUT_HOST_NAME)/api\?"
endif

# TARGETS

.PHONY: help
help: ## Display the available targets
	@echo -e "Available targets:\n"
	@cat Makefile | while IFS= read -r line; do \
	   if [[ "$$line" == "##" ]]; then \
			echo "" ; \
		elif [[ "$$line" =~ ^##\ (.*)$$ ]]; then \
			echo -e "\n$${BASH_REMATCH[1]}\n" ; \
		elif [[ "$$line" =~ ^([^:]+):(.*)##\ (.*)$$ ]]; then \
			echo -e "- make $${BASH_REMATCH[1]}    \t$${BASH_REMATCH[3]}" ; \
		fi ; \
	done

##

.PHONY: init
init: .env ## Check the dependencies and prompt to install if needed
	@which deno > /dev/null && echo "Deno is available" || echo "Install Deno:  curl -fsSL https://deno.land/install.sh | sh"
	@which bulloak > /dev/null && echo "bulloak is available" || echo "Install bulloak:  cargo install bulloak"

	@which forge > /dev/null || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

.PHONY: clean
clean: ## Clean the build artifacts
	rm -f $(TEST_TREE_FILES)
	rm -f $(TEST_TREE_MARKDOWN)
	rm -Rf ./out/* lcov.info* ./report/*

## Testing lifecycle:

.PHONY: test
test: ## Run unit tests, locally
	forge test $(VERBOSITY)

test-coverage: report/index.html ## Generate an HTML coverage report under ./report
	@which open > /dev/null && open report/index.html || echo -n
	@which xdg-open > /dev/null && xdg-open report/index.html || echo -n

report/index.html: lcov.info.pruned
	genhtml $^ -o report --branch-coverage

lcov.info.pruned: lcov.info
	lcov --remove $< -o ./$@ $^

lcov.info: $(TEST_COVERAGE_SRC_FILES)
	forge coverage --report lcov

##

sync-tests: $(TEST_TREE_FILES) ## Scaffold or sync tree files into solidity tests
	@for file in $^; do \
		if [ ! -f $${file%.tree}.t.sol ]; then \
			echo "[Scaffold]   $${file%.tree}.t.sol" ; \
			bulloak scaffold -s $(SOLIDITY_VERSION) --vm-skip -w $$file ; \
		else \
			echo "[Sync file]  $${file%.tree}.t.sol" ; \
			bulloak check --fix $$file ; \
		fi \
	done

check-tests: $(TEST_TREE_FILES) ## Checks if solidity files are out of sync
	bulloak check $^

markdown-tests: $(TEST_TREE_MARKDOWN) ## Generates a markdown file with the test definitions rendered as a tree

# Internal targets

# Generate a markdown file with the test trees
$(TEST_TREE_MARKDOWN): $(TEST_TREE_FILES)
	@echo "[Markdown]   TEST_TREE.md"
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

# Copy the .env files if not present
.env:
	cp .env.example .env
	@echo "NOTE: Edit the correct values of .env before you continue"

## Deployment targets:

.PHONY: predeploy
predeploy: ## Simulate a protocol deployment
	@echo "Simulating the deployment"
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

.PHONY: deploy
deploy: test ## Deploy the protocol and verify the source code
	@echo "Starting the deployment"
	@mkdir -p logs/
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		--retries 10 \
		--delay 8 \
		--broadcast \
		--verify \
		$(VERIFIER_TYPE_PARAM) \
		$(VERIFIER_URL_PARAM) \
		$(ETHERSCAN_API_KEY_PARAM) \
		$(VERBOSITY) | tee logs/$(DEPLOYMENT_LOG_FILE)

##

.PHONY: refund
refund: ## Refund the remaining balance left on the deployment account
	@echo "Refunding the remaining balance on $(DEPLOYMENT_ADDRESS)"
	@if [ -z $(REFUND_ADDRESS) -o $(REFUND_ADDRESS) = "0x0000000000000000000000000000000000000000" ]; then \
		echo "- The refund address is empty" ; \
		exit 1; \
	fi
	@BALANCE=$(shell cast balance $(DEPLOYMENT_ADDRESS) --rpc-url $(PRODNET_RPC_URL)) && \
		GAS_PRICE=$(shell cast gas-price --rpc-url $(PRODNET_RPC_URL)) && \
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
			--rpc-url $(PRODNET_RPC_URL) \
			--value $$REMAINING \
			$(REFUND_ADDRESS)
