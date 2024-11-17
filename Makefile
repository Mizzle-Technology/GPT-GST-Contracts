# Define variables
FORGE = forge
CAST = cast
DEPLOY_SCRIPT = script/Deploy.s.sol
TEST_SCRIPT = test

# Default target
all: compile deploy test

# Compile contracts
compile:
	@echo "Compiling contracts..."
	$(FORGE) clean && $(FORGE) build

# Deploy contracts
deploy: compile
	@echo "Deploying contracts..."
	$(FORGE) script $(DEPLOY_SCRIPT) --broadcast --verify --rpc-url <YOUR_RPC_URL>

# Run tests
test: compile
	@echo "Running tests..."
	$(FORGE) test -vvv

quick-test:
	@echo "Running tests..."
	$(FORGE) test -vvv

# Clean artifacts
clean:
	@echo "Cleaning artifacts..."
	rm -rf out cache

# Help
help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  compile  Compile the smart contracts"
	@echo "  deploy   Deploy the smart contracts"
	@echo "  test     Run the tests"
	@echo "  clean    Clean the artifacts"
	@echo "  help     Show this help message"

.PHONY: all compile deploy test clean help