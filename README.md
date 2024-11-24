# GoldPack Token & Gold Stable Yield Token Contracts

A set of smart contracts for managing the sale, minting, and burning of Gold Pack Tokens (GPT), including secure vaults and price calculation integration. This project leverages the Foundry framework for testing and deployment.

---

## Overview

This repository contains a suite of contracts and a utility library for managing a gold-backed ERC20 token (GPT), handling sales stages, secure withdrawals, token burning, and price calculations. Each contract is designed with upgradeability, security, and role-based access control.

The contracts included:

1. **GPT Contract**: A gold-backed ERC20 token with minting and burning capabilities.
2. **Sales Contract**: Manages the sales of GPT tokens across different sale stages with role-based access and signature verification.
3. **BurnVault**: Provides a time-delayed token burning vault for secure GPT token management.
4. **TradingVault**: A vault for managing withdrawals with threshold and delay restrictions.
5. **PriceCalculator Library**: A library for calculating GPT token prices based on gold and token price feeds.

---

## Contracts

### GPT Contract

The **GPT Contract** (`GoldPackToken.sol`) is an ERC20 token that represents a gold-backed currency. It integrates burn mechanics and access control to restrict minting and burning to specific roles.

- **Roles**: `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `SALES_ROLE`.
- **Tokenomics**: 1 GPT = 1/10,000 Troy ounce of gold.
- **Burning Mechanism**: Supports delayed burning through integration with the `BurnVault`.
- **Events**: `Mint`, `Burn`, `Paused`, `Unpaused`.

### Sales Contract

The **Sales Contract** (`SalesContract.sol`) manages GPT token sales across different stages with a signature-based authorization system and price calculations using Chainlink price feeds.

- **Sale Stages**: `PreMarketing`, `PreSale`, `PublicSale`, `SaleEnded`.
- **Roles**: `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `SALES_MANAGER_ROLE`.
- **Price Calculation**: Uses `PriceCalculator` for real-time price determination.
- **Events**: `TokensPurchased`, `RoundCreated`, `RoundActivated`, `RoundDeactivated`, `TrustedSignerUpdated`, `Paused`, `Unpaused`.

### BurnVault

The **BurnVault** (`BurnVault.sol`) is a secure vault that allows GPT token holders to deposit tokens for burning after a fixed delay.

- **Roles**: `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`.
- **Burn Delay**: Set to 7 days to prevent immediate burning.
- **Events**: `TokensDeposited`, `TokensBurned`.

### TradingVault

The **TradingVault** (`TradingVault.sol`) is a secure, upgradeable vault for managing withdrawals with a threshold and delay mechanism.

- **Roles**: `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`.
- **Withdrawal Threshold**: Limits on immediate withdrawals; higher amounts require queuing.
- **Withdrawal Delay**: Enforced delay for larger withdrawals.
- **Events**: `WithdrawalQueued`, `WithdrawalExecuted`, `WithdrawalCancelled`, `ImmediateWithdrawal`, `WithdrawalWalletUpdated`, `WithdrawalThresholdUpdated`.

### PriceCalculator Library

The **PriceCalculator** library calculates GPT token prices based on current gold prices and other payment token prices.

- **Functions**:
  - `calculateTokenAmount`: Calculates required tokens for a purchase.
  - `getLatestPrices`: Fetches latest prices from Chainlink feeds.
- **Dependencies**: `AggregatorV3Interface` from Chainlink.

---

## Setup and Installation

### Prerequisites

1. **Install Foundry**: Follow the [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation) if not already installed.
2. **Clone Repository**:

   ```bash
   gh repo clone Mizzle-Technology/GPT-GST-Contracts
   cd GPT-GST-Contracts

   ```

### Install Dependencies

```bash
forge install

```

### Compile Contracts

```bash
forge build
```

### Format

```jsx
forge fmt
```

### Gas Snapshots

```jsx
forge snapshot
```

### Help

```jsx
$ forge --help
$ anvil --help
$ cast --help
```

## Foundry Test Suite

---

This repository includes comprehensive tests using the Foundry framework to ensure the security and functionality of each contract.

### Run Tests

To execute all tests:

```bash
forge test -vvv

```

### Coverage

To generate a coverage report:

```bash
forge coverage

```

---

## Usage Guide

### Deploying Contracts

1. **GPT Contract**:
   Deploy `GoldPackToken` first, specifying any required initialization arguments.
2. **BurnVault and TradingVault**:
   Deploy each vault separately, initializing each with the appropriate roles and settings.
3. **Sales Contract**:
   Deploy `SalesContract` with required initial values, including `trustedSigner` and price feed addresses.
4. **Link Contracts**:
   Link `BurnVault` and `TradingVault` to `SalesContract` for secure management of token burning and withdrawals.

### Interacting with Contracts

### 1. **Minting GPT Tokens**

Only `SALES_ROLE` members can mint GPT tokens:

```solidity
gptToken.mint(to, amount);

```

### 2. **Burning GPT Tokens**

Tokens deposited to `BurnVault` can be burned after a delay:

```solidity
burnVault.depositTokens(user, amount);
burnVault.burnTokens(user);

```

### 3. **Purchasing Tokens in the Sales Contract**

Purchase GPT tokens in public sale using `SalesContract.authorizePurchase` with a verified order:

```solidity
salesContract.authorizePurchase(order);

```

### 4. **Managing Withdrawals**

Queue a withdrawal with delay or perform an immediate withdrawal if below the threshold:

```solidity
tradingVault.queueWithdrawal(tokenAddress, amount);
tradingVault.withdraw(tokenAddress, amount);

```

### Upgradeability

The contracts support the UUPS upgradeable pattern, allowing future upgrades.

To upgrade a contract:

1. Deploy a new implementation.
2. Use the `upgrade` function in the UUPS proxy with the new contract address.

### **License**

This project is licensed under the MIT License.
