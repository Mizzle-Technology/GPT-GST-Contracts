# Define variables
HARDHAT = npx hardhat
CAST = cast
DEPLOY_SCRIPT = script/Deploy.s.sol
TEST_SCRIPT = test
TEST_NAME ?=

# Default target
all: compile deploy test typechain

# Compile contracts
compile:
	@echo "Compiling contracts..."
	$(HARDHAT) clean && $(HARDHAT) compile
	npm run format
	npm run lint:fix

# Deploy contracts
deploy: compile
	@echo "Deploying contracts..."
	$(FORGE) script $(DEPLOY_SCRIPT) --broadcast --verify --rpc-url <YOUR_RPC_URL>

# Testnet deploy
testnet-deploy:
	@echo "Deploying contracts to testnet..."
	$(HARDHAT) compile
	$(HARDHAT) run scripts/test-deploy.ts --network sepolia

# Run tests
test: compile
	@echo "Running tests..."
	$(HARDHAT) test

# typechain
typechain:
	@echo "Generating typechain types..."
	$(HARDHAT) typechain

# Clean artifacts
clean:
	@echo "Cleaning artifacts..."
	rm -rf out cache artifacts typechain-types

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