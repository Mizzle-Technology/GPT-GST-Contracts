import { expect } from 'chai';
import { ethers } from 'hardhat';
import { CalculationLibTest, MockAggregator } from '../typechain-types';

describe('CalculationLib', () => {
  let calculationLib: CalculationLibTest;
  let mockPriceFeed: MockAggregator;

  beforeEach(async () => {
    // Deploy mock price feed
    const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator');
    mockPriceFeed = (await MockAggregatorFactory.deploy()) as unknown as MockAggregator;

    // Deploy test contract
    const CalculationLibTest = await ethers.getContractFactory('CalculationLibTest');
    calculationLib = (await CalculationLibTest.deploy()) as unknown as CalculationLibTest;
  });

  describe('calculatePaymentTokenAmount', () => {
    it('should calculate payment token amount correctly', async () => {
      const goldPrice = ethers.parseUnits('2000', 8); // $2000 per troy ounce
      const tokenPrice = ethers.parseUnits('1', 8); // $1 per token (e.g., USDC)
      const gptAmount = ethers.parseUnits('5000', 6); // 5000 GPT tokens
      const tokenDecimals = 6; // USDC has 6 decimals
      const tokensPerTroyOunce = ethers.parseUnits('10000', 6); // 10000 GPT per troy ounce

      const paymentTokenAmount = await calculationLib.calculatePaymentTokenAmount(
        goldPrice,
        tokenPrice,
        gptAmount,
        tokenDecimals,
        tokensPerTroyOunce,
      );

      // Expected: (2000 * 5000) / 10000 = 1000 USDC
      expect(paymentTokenAmount).to.equal(ethers.parseUnits('1000', 6));
    });

    it('should revert with invalid inputs', async () => {
      const tokenDecimals = 6;
      const tokensPerTroyOunce = ethers.parseUnits('10000', 6);

      // Test invalid gold price
      await expect(
        calculationLib.calculatePaymentTokenAmount(
          0,
          ethers.parseUnits('1', 8),
          ethers.parseUnits('5000', 6),
          tokenDecimals,
          tokensPerTroyOunce,
        ),
      ).to.be.revertedWith('Invalid gold price');

      // Test invalid token price
      await expect(
        calculationLib.calculatePaymentTokenAmount(
          ethers.parseUnits('2000', 8),
          0,
          ethers.parseUnits('5000', 6),
          tokenDecimals,
          tokensPerTroyOunce,
        ),
      ).to.be.revertedWith('Invalid token price');

      // Test invalid GPT amount
      await expect(
        calculationLib.calculatePaymentTokenAmount(
          ethers.parseUnits('2000', 8),
          ethers.parseUnits('1', 8),
          0,
          tokenDecimals,
          tokensPerTroyOunce,
        ),
      ).to.be.revertedWith('GPT amount must be greater than zero');
    });
  });

  describe('calculateGptAmount', () => {
    it('should calculate GPT token amount correctly', async () => {
      const goldPrice = ethers.parseUnits('2000', 8); // $2000 per troy ounce
      const tokenPrice = ethers.parseUnits('1', 8); // $1 per token
      const paymentTokenAmount = ethers.parseUnits('1000', 6); // 1000 USDC
      const tokenDecimals = 6;
      const tokensPerTroyOunce = ethers.parseUnits('10000', 6);

      const gptAmount = await calculationLib.calculateGptAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenDecimals,
        tokensPerTroyOunce,
      );

      // Expected: (1000 * 1 * 10000) / (2000) = 5000 GPT
      expect(gptAmount).to.equal(ethers.parseUnits('5000', 6));
    });

    it('should revert with invalid inputs', async () => {
      const tokenDecimals = 6;
      const tokensPerTroyOunce = ethers.parseUnits('10000', 6);

      // Test invalid gold price
      await expect(
        calculationLib.calculateGptAmount(
          0,
          ethers.parseUnits('1', 8),
          ethers.parseUnits('1000', 6),
          tokenDecimals,
          tokensPerTroyOunce,
        ),
      ).to.be.revertedWith('Invalid gold price');

      // Test invalid token price
      await expect(
        calculationLib.calculateGptAmount(
          ethers.parseUnits('2000', 8),
          0,
          ethers.parseUnits('1000', 6),
          tokenDecimals,
          tokensPerTroyOunce,
        ),
      ).to.be.revertedWith('Invalid token price');
    });
  });

  describe('getLatestPrice', () => {
    it('should get latest price correctly', async () => {
      const mockPrice = ethers.parseUnits('2000', 8);
      // Use current block timestamp
      const latestBlock = await ethers.provider.getBlock('latest');
      const mockTimestamp = latestBlock!.timestamp;

      await mockPriceFeed.setRoundData(
        1, // roundId
        mockPrice, // price
        mockTimestamp, // startedAt
        mockTimestamp, // updatedAt
        1, // answeredInRound
      );

      const [price, updatedAt] = await calculationLib.getLatestPrice(
        await mockPriceFeed.getAddress(),
      );

      expect(price).to.equal(mockPrice);
      expect(updatedAt).to.equal(mockTimestamp);
    });

    it('should revert if price is stale', async () => {
      const mockPrice = ethers.parseUnits('2000', 8);
      const staleTimestamp = Math.floor(Date.now() / 1000) - 7200; // 2 hours old

      await mockPriceFeed.setRoundData(1, mockPrice, staleTimestamp, staleTimestamp, 1);

      await expect(
        calculationLib.getLatestPrice(await mockPriceFeed.getAddress()),
      ).to.be.revertedWithCustomError(calculationLib, 'TokenPriceStale');
    });

    it('should revert if price is invalid', async () => {
      const currentTimestamp = Math.floor(Date.now() / 1000);
      await mockPriceFeed.setRoundData(1, 0, currentTimestamp, currentTimestamp, 1);

      await expect(
        calculationLib.getLatestPrice(await mockPriceFeed.getAddress()),
      ).to.be.revertedWithCustomError(calculationLib, 'InvalidTokenPrice');
    });
  });
});
