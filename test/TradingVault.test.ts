// test/TradingVault.test.ts

import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Signer } from 'ethers';
import {
  TradingVault,
  TradingVaultV2,
  GoldPackToken,
  BurnVault,
  MockERC20,
  MockAggregator,
} from '../typechain-types'; // Adjust the import path based on your setup
import { time } from '@nomicfoundation/hardhat-network-helpers';

describe('TradingVault Upgrade Tests', function () {
  let deployer: Signer;
  let superAdmin: Signer;
  let admin: Signer;
  let sales: Signer;
  let nonAdmin: Signer;

  let safeWallet: Signer;
  let newSafeWallet: Signer;

  // Contracts
  let usdc: MockERC20;
  let goldPriceFeed: MockAggregator;
  let usdcPriceFeed: MockAggregator;
  let burnVault: BurnVault;
  let gptToken: GoldPackToken;
  let tradingVault: TradingVault;

  // Constants
  const ONE_DAY_IN_SECONDS = 86400;

  beforeEach(async function () {
    // Get the signers
    [deployer, superAdmin, admin, nonAdmin, sales, safeWallet, newSafeWallet] =
      await ethers.getSigners();

    // Deploy Mock Contracts
    const MockERC20Factory = await ethers.getContractFactory('MockERC20', deployer);
    usdc = (await MockERC20Factory.deploy()) as MockERC20;
    await usdc.initialize('USDC', 'USD Coin', 6);

    const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator', deployer);
    goldPriceFeed = (await MockAggregatorFactory.deploy()) as MockAggregator;
    usdcPriceFeed = (await MockAggregatorFactory.deploy()) as MockAggregator;

    // Set initial prices
    await goldPriceFeed.setPrice(ethers.parseUnits('2000', 8)); // $2000/oz with 8 decimals
    await usdcPriceFeed.setPrice(ethers.parseUnits('1', 8)); // $1/USDC with 8 decimals

    // Deploy the BurnVault proxy
    const BurnVaultFactory = await ethers.getContractFactory('BurnVault', deployer);
    burnVault = (await upgrades.deployProxy(
      BurnVaultFactory,
      [await superAdmin.getAddress(), await admin.getAddress()],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as BurnVault;
    await burnVault.waitForDeployment();

    // Deploy the GoldPackToken
    const GoldPackTokenFactory = await ethers.getContractFactory('GoldPackToken', deployer);
    gptToken = (await upgrades.deployProxy(
      GoldPackTokenFactory,
      [await superAdmin.getAddress(), await admin.getAddress(), await sales.getAddress()],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as GoldPackToken;
    await gptToken.waitForDeployment();

    // bind the Burn vault with GPT token
    await burnVault.connect(admin).updateAcceptedTokens(await gptToken.getAddress());

    // Deploy the initial TradingVault proxy
    const TradingVaultFactory = await ethers.getContractFactory('TradingVault', deployer);
    tradingVault = (await upgrades.deployProxy(
      TradingVaultFactory,
      [await safeWallet.getAddress(), await admin.getAddress(), await superAdmin.getAddress()],
      { initializer: 'initialize' },
    )) as unknown as TradingVault;
    await tradingVault.waitForDeployment();
  });

  // === Tests for Initialize ===
  it('initialize test', function () {
    it('should initialize the contract with the correct values', async function () {
      const adminRole = await tradingVault.ADMIN_ROLE();
      const defaultAdminRole = await tradingVault.DEFAULT_ADMIN_ROLE();

      expect(await tradingVault.hasRole(adminRole, await admin.getAddress())).to.be.true;
      expect(await tradingVault.hasRole(defaultAdminRole, await superAdmin.getAddress())).to.be
        .true;
      await expect(tradingVault.safeWallet()).to.eventually.equal(await safeWallet.getAddress());

      const withdrawalThreshold = await tradingVault.WITHDRAWAL_THRESHOLD();
      expect(withdrawalThreshold).to.equal(100000 * 10 ** 6);
    });
  });

  // === Tests for queueWithdrawal ===
  describe('queueWithdrawal', function () {
    beforeEach(async function () {
      // Setup USDC balance in vault
      await usdc.mint(await tradingVault.getAddress(), ethers.parseUnits('1000000', 6));
    });

    it('should queue withdrawal successfully', async function () {
      const amount = ethers.parseUnits('1000', 6);

      const tx = await tradingVault.connect(admin).queueWithdrawal(await usdc.getAddress(), amount);
      const block = await ethers.provider.getBlock(tx.blockNumber!);
      const requestId = ethers.solidityPackedKeccak256(
        ['address', 'uint256', 'uint256'],
        [await usdc.getAddress(), amount, block!.timestamp],
      );

      // Verify event emission
      await expect(tx)
        .to.emit(tradingVault, 'WithdrawalQueued')
        .withArgs(
          requestId,
          await usdc.getAddress(),
          amount,
          await tradingVault.safeWallet(),
          block!.timestamp,
          block!.timestamp + 86400, // WITHDRAWAL_DELAY (1 day)
        );

      // Verify request storage
      const request = await tradingVault.withdrawalRequests(requestId);
      expect(request.token).to.equal(await usdc.getAddress());
      expect(request.amount).to.equal(amount);
      expect(request.transfer_to).to.equal(await tradingVault.safeWallet());
      expect(request.requestTime).to.equal(block!.timestamp);
      expect(request.expiry).to.equal(block!.timestamp + 86400);
      expect(request.executed).to.be.false;
      expect(request.cancelled).to.be.false;
    });

    it('should revert if caller is not admin', async function () {
      const amount = ethers.parseUnits('1000', 6);

      await expect(tradingVault.connect(nonAdmin).queueWithdrawal(await usdc.getAddress(), amount))
        .to.be.revertedWithCustomError(tradingVault, 'AdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());
    });

    it('should revert if amount is zero', async function () {
      await expect(tradingVault.connect(admin).queueWithdrawal(await usdc.getAddress(), 0))
        .to.be.revertedWithCustomError(tradingVault, 'InvalidAmount')
        .withArgs(0);
    });

    it('should revert if token address is zero', async function () {
      const amount = ethers.parseUnits('1000', 6);

      await expect(
        tradingVault.connect(admin).queueWithdrawal(ethers.ZeroAddress, amount),
      ).to.be.revertedWithCustomError(tradingVault, 'AddressCannotBeZero');
    });

    it('should revert if vault has insufficient balance', async function () {
      const amount = ethers.parseUnits('2000000', 6); // More than vault balance
      const contractBalance = await usdc.balanceOf(await tradingVault.getAddress());
      await expect(tradingVault.connect(admin).queueWithdrawal(await usdc.getAddress(), amount))
        .to.be.revertedWithCustomError(tradingVault, 'InsufficientBalance')
        .withArgs(contractBalance, amount);
    });
  });

  describe('executeWithdrawal', function () {
    let requestId: string;
    const withdrawAmount = ethers.parseUnits('1000', 6);

    beforeEach(async function () {
      // Setup USDC balance in vault
      await usdc.mint(await tradingVault.getAddress(), ethers.parseUnits('1000000', 6));

      // Queue a withdrawal first
      const tx = await tradingVault
        .connect(admin)
        .queueWithdrawal(await usdc.getAddress(), withdrawAmount);

      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error('Transaction failed');
      }
      const event = receipt.logs[0];
      requestId = tradingVault.interface.parseLog(event)?.args.requestId;

      if (!requestId) {
        throw new Error('Request ID not found');
      }
    });

    it('should execute withdrawal successfully after delay', async function () {
      // Fast forward time past the delay

      await time.increase(ONE_DAY_IN_SECONDS); // 1 day + 1 second

      const safeWallet = await tradingVault.safeWallet();
      const vaultBalanceBefore = await usdc.balanceOf(await tradingVault.getAddress());
      const recipientBalanceBefore = await usdc.balanceOf(safeWallet);

      const tx = await tradingVault.connect(admin).executeWithdrawal(requestId);
      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error('Transaction failed');
      }
      const block = await ethers.provider.getBlock(tx.blockNumber!);
      const blockTimestamp = block!.timestamp;

      // Check event emission with all expected parameters
      await expect(tx)
        .to.emit(tradingVault, 'WithdrawalExecuted')
        .withArgs(requestId, await usdc.getAddress(), withdrawAmount, safeWallet, blockTimestamp);

      // Check balances updated correctly
      expect(await usdc.balanceOf(await tradingVault.getAddress())).to.equal(
        vaultBalanceBefore - withdrawAmount,
      );
      expect(await usdc.balanceOf(safeWallet)).to.equal(recipientBalanceBefore + withdrawAmount);

      // Check request marked as executed
      const updatedRequest = await tradingVault.withdrawalRequests(requestId);
      expect(updatedRequest.executed).to.be.true;
    });

    it('should revert if caller is not admin', async function () {
      await ethers.provider.send('evm_increaseTime', [86401]);

      await expect(tradingVault.connect(nonAdmin).executeWithdrawal(requestId))
        .to.be.revertedWithCustomError(tradingVault, 'AdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());
    });

    it('should revert if withdrawal delay has not passed', async function () {
      await ethers.provider.send('evm_increaseTime', [86399]); // 1 day - 1 second

      await expect(
        tradingVault.connect(admin).executeWithdrawal(requestId),
      ).to.be.revertedWithCustomError(tradingVault, 'WithdrawalDelayNotMet');
    });

    it('should revert if request does not exist', async function () {
      const nonExistentRequestId = ethers.keccak256(ethers.toUtf8Bytes('non-existent'));
      await ethers.provider.send('evm_increaseTime', [86401]);

      await expect(
        tradingVault.connect(admin).executeWithdrawal(nonExistentRequestId),
      ).to.be.revertedWithCustomError(tradingVault, 'WithdrawalRequestNotFound');
    });

    it('should revert if request already executed', async function () {
      await time.increase(ONE_DAY_IN_SECONDS);

      // Execute first time
      await tradingVault.connect(admin).executeWithdrawal(requestId);

      // Try to execute again
      await expect(
        tradingVault.connect(admin).executeWithdrawal(requestId),
      ).to.be.revertedWithCustomError(tradingVault, 'WithdrawalAlreadyExecuted');
    });

    it('should revert if request is cancelled', async function () {
      // Fast forward time past the delay
      const TWO_DAYS_IN_SECONDS = ONE_DAY_IN_SECONDS * 2;
      await time.increase(TWO_DAYS_IN_SECONDS);
      // Cancel the request
      await tradingVault.connect(admin).cancelWithdrawal(requestId);

      await expect(
        tradingVault.connect(admin).executeWithdrawal(requestId),
      ).to.be.revertedWithCustomError(tradingVault, 'WithdrawalAlreadyCancelled');
    });
  });

  describe('withdraw', function () {
    beforeEach(async function () {
      // Setup USDC balance in vault
      await usdc.mint(await tradingVault.getAddress(), ethers.parseUnits('100000', 6));
    });

    it('should withdraw tokens successfully within threshold', async function () {
      const amount = ethers.parseUnits('50000', 6); // 50k USDC (below 100k threshold)
      const safeWalletAddress = await tradingVault.safeWallet();

      const vaultBalanceBefore = await usdc.balanceOf(await tradingVault.getAddress());
      const safeWalletBalanceBefore = await usdc.balanceOf(safeWalletAddress);

      const tx = await tradingVault.connect(admin).withdraw(await usdc.getAddress(), amount);

      // Check event emission
      await expect(tx)
        .to.emit(tradingVault, 'ImmediateWithdrawal')
        .withArgs(await usdc.getAddress(), amount, safeWalletAddress, await time.latest());

      // Check balances
      expect(await usdc.balanceOf(await tradingVault.getAddress())).to.equal(
        vaultBalanceBefore - amount,
      );
      expect(await usdc.balanceOf(safeWalletAddress)).to.equal(safeWalletBalanceBefore + amount);
    });

    it('should revert if amount exceeds threshold', async function () {
      const amount = ethers.parseUnits('150000', 6); // 150k USDC (above 100k threshold)
      const threshold = await tradingVault.WITHDRAWAL_THRESHOLD();

      await expect(tradingVault.connect(admin).withdraw(await usdc.getAddress(), amount))
        .to.be.revertedWithCustomError(tradingVault, 'AmountExceedsThreshold')
        .withArgs(amount, threshold);
    });

    it('should revert if caller is not admin', async function () {
      const amount = ethers.parseUnits('50000', 6);

      await expect(tradingVault.connect(nonAdmin).withdraw(await usdc.getAddress(), amount))
        .to.be.revertedWithCustomError(tradingVault, 'AdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());
    });

    it('should revert if amount is zero', async function () {
      await expect(tradingVault.connect(admin).withdraw(await usdc.getAddress(), 0))
        .to.be.revertedWithCustomError(tradingVault, 'InvalidAmount')
        .withArgs(0);
    });

    it('should revert if token address is zero', async function () {
      const amount = ethers.parseUnits('50000', 6);

      await expect(
        tradingVault.connect(admin).withdraw(ethers.ZeroAddress, amount),
      ).to.be.revertedWithCustomError(tradingVault, 'AddressCannotBeZero');
    });

    it('should revert if vault has insufficient balance', async function () {
      const amount = ethers.parseUnits('70000', 6); // More than vault balance
      const contractBalance = await usdc.balanceOf(await tradingVault.getAddress());
      // withdraw first time
      await tradingVault.connect(admin).withdraw(await usdc.getAddress(), amount);

      // withdraw second time
      await expect(tradingVault.connect(admin).withdraw(await usdc.getAddress(), amount))
        .to.be.revertedWithCustomError(tradingVault, 'InsufficientBalance')
        .withArgs(contractBalance - amount, amount);
    });

    it('should revert when contract is paused', async function () {
      const amount = ethers.parseUnits('50000', 6);

      // Pause the contract
      await tradingVault.connect(admin).pause();

      await expect(
        tradingVault.connect(admin).withdraw(await usdc.getAddress(), amount),
      ).to.be.revertedWithCustomError(tradingVault, 'EnforcedPause');
    });
  });

  // === Tests for setWithdrawalWallet ===

  describe('setWithdrawalWallet', function () {
    it('should allow superAdmin to set a new withdrawal wallet', async function () {
      await expect(tradingVault.connect(superAdmin).setWithdrawalWallet(newSafeWallet))
        .to.emit(tradingVault, 'WithdrawalWalletUpdated')
        .withArgs(newSafeWallet);

      const currentWallet = await tradingVault.safeWallet();
      expect(currentWallet).to.equal(newSafeWallet);
    });

    it('should revert when a non-admin tries to set the withdrawal wallet', async function () {
      await expect(tradingVault.connect(nonAdmin).setWithdrawalWallet(newSafeWallet))
        .to.be.revertedWithCustomError(tradingVault, 'DefaultAdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());

      const currentWallet = await tradingVault.safeWallet();
      expect(currentWallet).to.equal(safeWallet);
    });

    it('should revert when setting the withdrawal wallet to the zero address', async function () {
      await expect(
        tradingVault.connect(superAdmin).setWithdrawalWallet(ethers.ZeroAddress),
      ).to.be.revertedWith('Invalid wallet address');
    });

    it('should revert when setting the withdrawal wallet to the same address', async function () {
      await expect(
        tradingVault.connect(superAdmin).setWithdrawalWallet(safeWallet),
      ).to.be.revertedWith('Same wallet address');
    });
  });

  // === Tests for setWithdrawalThreshold ===

  describe('setWithdrawalThreshold', function () {
    it('should allow superAdmin to set a new withdrawal threshold', async function () {
      const newThreshold = ethers.parseUnits('500000', 6); // 500,000 USDC

      await expect(tradingVault.connect(superAdmin).setWithdrawalThreshold(newThreshold))
        .to.emit(tradingVault, 'WithdrawalThresholdUpdated')
        .withArgs(newThreshold);

      const currentThreshold = await tradingVault.WITHDRAWAL_THRESHOLD();
      expect(currentThreshold).to.equal(newThreshold);
    });

    it('should revert when a non-admin tries to set the withdrawal threshold', async function () {
      const newThreshold = ethers.parseUnits('500000', 6); // 500,000 USDC

      await expect(tradingVault.connect(nonAdmin).setWithdrawalThreshold(newThreshold))
        .to.be.revertedWithCustomError(tradingVault, 'DefaultAdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());

      const currentThreshold = await tradingVault.WITHDRAWAL_THRESHOLD();
      expect(currentThreshold).to.not.equal(newThreshold); // Assuming initial threshold is 0
    });

    it('should revert when setting the withdrawal threshold to zero', async function () {
      await expect(tradingVault.connect(superAdmin).setWithdrawalThreshold(0)).to.be.revertedWith(
        'Threshold must be greater than 0',
      );
    });

    it('should revert when setting the withdrawal threshold to the same value', async function () {
      const initialThreshold = await tradingVault.WITHDRAWAL_THRESHOLD();

      await expect(
        tradingVault.connect(superAdmin).setWithdrawalThreshold(initialThreshold),
      ).to.be.revertedWith('Same threshold');
    });
  });

  // === Tests for Pausable Functions ===

  describe('Pausable Functions', function () {
    it('should allow admin to pause the contract', async function () {
      await expect(tradingVault.connect(admin).pause())
        .to.emit(tradingVault, 'Paused')
        .withArgs(await admin.getAddress());

      const isPaused = await tradingVault.paused();
      expect(isPaused).to.be.true;
    });

    it('should revert when a non-admin tries to pause the contract', async function () {
      await expect(tradingVault.connect(nonAdmin).pause())
        .to.be.revertedWithCustomError(tradingVault, 'AdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());

      const isPaused = await tradingVault.paused();
      expect(isPaused).to.be.false;
    });

    it('should allow admin to unpause the contract', async function () {
      // First, pause the contract
      await tradingVault.connect(admin).pause();
      expect(await tradingVault.paused()).to.be.true;

      // Unpause
      await expect(tradingVault.connect(admin).unpause())
        .to.emit(tradingVault, 'Unpaused')
        .withArgs(await admin.getAddress());

      const isPaused = await tradingVault.paused();
      expect(isPaused).to.be.false;
    });

    it('should revert when a non-admin tries to unpause the contract', async function () {
      // First, pause the contract
      await tradingVault.connect(admin).pause();
      expect(await tradingVault.paused()).to.be.true;

      // Attempt to unpause as nonAdmin
      await expect(tradingVault.connect(nonAdmin).unpause())
        .to.be.revertedWithCustomError(tradingVault, 'AdminRoleNotGranted')
        .withArgs(await nonAdmin.getAddress());

      const isPaused = await tradingVault.paused();
      expect(isPaused).to.be.true;
    });
  });

  // === Tests for Upgrade to V2 ===

  describe('Upgrade to V2', function () {
    it('should upgrade to V2 successfully and preserve state', async function () {
      // Deploy V2 Implementation
      const TradingVaultV2Factory = await ethers.getContractFactory('TradingVaultV2', superAdmin);

      // Perform the upgrade
      const upgradedTradingVault = (await upgrades.upgradeProxy(
        await tradingVault.getAddress(),
        TradingVaultV2Factory.connect(superAdmin),
      )) as unknown as TradingVaultV2;

      // Set the new withdrawal wallet using V2 function
      await expect(upgradedTradingVault.connect(superAdmin).setWithdrawalWallet(newSafeWallet))
        .to.emit(upgradedTradingVault, 'WithdrawalWalletUpdated')
        .withArgs(newSafeWallet);

      // Verify the upgrade was successful by calling a V2 function
      const version = await upgradedTradingVault.version();
      expect(version).to.equal('V2', 'Upgrade to V2 failed');

      // Verify state preservation: safeWallet should be updated
      const currentSafeWallet = await upgradedTradingVault.safeWallet();
      expect(currentSafeWallet).to.equal(newSafeWallet, 'Safe wallet not updated correctly');
    });
  });
});
