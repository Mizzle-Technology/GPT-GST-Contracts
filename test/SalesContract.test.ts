import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import {
  GoldPackToken,
  SalesContract,
  TradingVault,
  BurnVault,
  MockERC20,
  MockAggregator,
} from '../typechain-types';

// Replace the SaleStage import with this enum definition
enum SaleStage {
  PreMarketing,
  PreSale,
  PublicSale,
  SaleEnded,
}

describe('SalesContract Tests', function () {
  // Constants
  const USDC_DECIMALS = 6;
  const GPT_DECIMALS = 6;

  // Contract instances
  let gptToken: GoldPackToken;
  let salesContract: SalesContract;
  let tradingVault: TradingVault;
  let burnVault: BurnVault;
  let usdc: MockERC20;
  let goldPriceFeed: MockAggregator;
  let usdcPriceFeed: MockAggregator;

  // Signers
  let superAdmin: SignerWithAddress;
  let admin: SignerWithAddress;
  let sales: SignerWithAddress;
  let safeWallet: SignerWithAddress;
  let user: SignerWithAddress;
  let relayer: SignerWithAddress;

  beforeEach(async function () {
    // Get signers
    [superAdmin, admin, sales, safeWallet, user, relayer] = await ethers.getSigners();

    // Deploy mocks
    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    usdc = await MockERC20Factory.deploy();
    await usdc.initialize('USDC', 'USDC', USDC_DECIMALS);

    const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator');
    goldPriceFeed = await MockAggregatorFactory.deploy();
    await goldPriceFeed.setPrice(ethers.parseUnits('2000', 8)); // $2000/oz

    usdcPriceFeed = await MockAggregatorFactory.deploy();
    await usdcPriceFeed.setPrice(ethers.parseUnits('1', 8)); // $1/USDC

    // Deploy contracts
    const BurnVaultFactory = await ethers.getContractFactory('BurnVault');
    burnVault = (await upgrades.deployProxy(BurnVaultFactory, [superAdmin.address, admin.address], {
      initializer: 'initialize',
    })) as unknown as BurnVault;
    const GoldPackTokenFactory = await ethers.getContractFactory('GoldPackToken');
    gptToken = (await upgrades.deployProxy(
      GoldPackTokenFactory,
      [superAdmin.address, admin.address, sales.address],
      {
        initializer: 'initialize',
      },
    )) as unknown as GoldPackToken;

    const TradingVaultFactory = await ethers.getContractFactory('TradingVault');
    tradingVault = (await upgrades.deployProxy(
      TradingVaultFactory,
      [safeWallet.address, admin.address, superAdmin.address],
      {
        initializer: 'initialize',
      },
    )) as unknown as TradingVault;
    const SalesContractFactory = await ethers.getContractFactory('SalesContract');
    salesContract = (await upgrades.deployProxy(
      SalesContractFactory,
      [
        superAdmin.address,
        admin.address,
        sales.address,
        await gptToken.getAddress(),
        await goldPriceFeed.getAddress(),
        await relayer.getAddress(),
        await tradingVault.getAddress(),
      ],
      {
        initializer: 'initialize',
      },
    )) as unknown as SalesContract;

    // Setup
    await burnVault.connect(admin).updateAcceptedTokens(await gptToken.getAddress());
    await gptToken.setBurnVault(await burnVault.getAddress());
    await salesContract.addAcceptedToken(
      await usdc.getAddress(),
      await usdcPriceFeed.getAddress(),
      USDC_DECIMALS,
    );
    await gptToken.grantRole(await gptToken.SALES_ROLE(), await salesContract.getAddress());
  });

  it('should set up contracts correctly', async function () {
    expect(await gptToken.getAddress()).to.equal(await salesContract.gptToken());
    expect(await goldPriceFeed.getAddress()).to.equal(await salesContract.goldPriceFeed());
    expect(await tradingVault.getAddress()).to.equal(await salesContract.tradingVault());
    expect(await salesContract.DOMAIN_SEPARATOR()).to.not.equal(ethers.ZeroAddress);
    expect(await salesContract.trustedSigner()).to.equal(relayer.address);
    expect(await salesContract.connect(admin).acceptedTokens(await usdc.getAddress())).to.not.equal(
      ethers.ZeroAddress,
    );
    expect(await salesContract.trustedSigner()).to.equal(relayer.address);
  });

  describe('Authorize Purchase', async () => {
    let currentRoundId: string;
    let currentTime: number;

    this.beforeEach(async () => {
      currentTime = await time.latest();
      // Create and activate round
      const createdRoundTx = await salesContract
        .connect(sales)
        .createRound(
          ethers.parseUnits('100000', GPT_DECIMALS),
          currentTime,
          currentTime + 24 * 60 * 60,
        );
      const receipt = await createdRoundTx.wait();
      if (!receipt) {
        throw new Error('Round creation failed');
      }
      // retrieve currentRoundId from event
      const roundCreatedEvent = receipt.logs.find(
        (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
      );

      if (!roundCreatedEvent) {
        throw new Error('Round creation event not found');
      }

      const parseLog = salesContract.interface.parseLog(roundCreatedEvent);
      currentRoundId = parseLog?.args[0];
    });

    it('should authorize purchase successfully', async function () {
      // Mint USDC to user
      await usdc.mint(user.address, ethers.parseUnits('2000', 6));

      // expect the round to be pre marketing
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PreMarketing);

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      // expect the round to be public sale
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PublicSale);

      // check the public sale stage

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      order.userSignature = userSignature;

      // check the trusted signer
      expect(await salesContract.trustedSigner()).to.equal(relayer.address);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      // Verify the signatures are proper length (65 bytes = 132 chars including '0x')
      expect(order.userSignature.length).to.equal(132);
      expect(relayerSignature.length).to.equal(132);
      order.relayerSignature = relayerSignature;

      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('2000', 6));

      // Execute purchase
      await salesContract.connect(user).authorizePurchase(order);

      // close the round
      await salesContract.connect(sales).setSaleStage(SaleStage.SaleEnded, currentRoundId);

      // Verify results
      expect(await gptToken.balanceOf(user.address)).to.equal(order.gptAmount);
      expect(await usdc.balanceOf(user.address)).to.equal(0);
      expect(await salesContract.nonces(user.address)).to.equal(1);
    });

    it('should fail purchase with invalid nonce', async function () {
      // check the round is active
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PreMarketing);

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 1, // Invalid nonce (should be 0)
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
      };

      // Generate signatures
      const userSignature = await getUserDigest(salesContract, user, order);

      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      // Approve USDC
      await usdc
        .connect(user)
        .approve(await tradingVault.getAddress(), ethers.parseUnits('2000', USDC_DECIMALS));

      // Attempt purchase
      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'InvalidNonce');
    });

    it('should allow multiple purchases by same user', async function () {
      // Mint USDC to user
      await usdc.mint(user.address, ethers.parseUnits('2000', USDC_DECIMALS));

      // expect the round to be pre marketing
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PreMarketing);

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      // First purchase
      const order1 = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('5000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
      };

      // Generate signatures for first order;
      const userSignature1 = await getUserDigest(salesContract, user, order1);

      const relayerSignature1 = await getUserDigest(salesContract, relayer, order1);

      // Approve and execute first purchase
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('1000', USDC_DECIMALS));
      await salesContract.connect(user).authorizePurchase({
        ...order1,
        userSignature: userSignature1,
        relayerSignature: relayerSignature1,
      });

      // Second purchase
      const order2 = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('3000', GPT_DECIMALS),
        nonce: 1,
        expiry: currentTime + 7200,
        paymentToken: await usdc.getAddress(),
      };

      // Generate signatures for second order
      const userSignature2 = await getUserDigest(salesContract, user, order2);

      const relayerSignature2 = await getUserDigest(salesContract, relayer, order2);

      // Approve and execute second purchase
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('1000', USDC_DECIMALS));
      await salesContract.connect(user).authorizePurchase({
        ...order2,
        userSignature: userSignature2,
        relayerSignature: relayerSignature2,
      });

      // close the round
      await salesContract.connect(sales).setSaleStage(SaleStage.SaleEnded, currentRoundId);

      // Verify results
      expect(await usdc.balanceOf(user.address)).to.equal(ethers.parseUnits('400', USDC_DECIMALS));
      expect(await gptToken.balanceOf(user.address)).to.equal(
        ethers.parseUnits('8000', GPT_DECIMALS),
      );
      expect(await salesContract.nonces(user.address)).to.equal(2);
    });

    it('should revert when signature is expired', async function () {
      // Advance block timestamp
      const twoHours = 2 * 60 * 60;
      await time.increase(twoHours);
      const currentTime = await time.latest();

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      // Create order with expired signature
      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime - 60 * 60, // 1 hour ago (expired)
        paymentToken: await usdc.getAddress(),
      };

      // Generate signatures
      const userSignature = await getUserDigest(salesContract, user, order);

      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      // Approve USDC
      await usdc
        .connect(user)
        .approve(await tradingVault.getAddress(), ethers.parseUnits('2000', USDC_DECIMALS));

      // Attempt purchase and expect revert
      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'OrderAlreadyExpired');
    });

    it('should not allow purchase with invalid payment token', async function () {
      const invalidToken = await (await ethers.getContractFactory('MockERC20')).deploy();
      await invalidToken.initialize('Invalid', 'INV', 18);

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await invalidToken.getAddress(),
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);
      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      )
        .to.be.revertedWithCustomError(salesContract, 'TokenNotAccepted')
        .withArgs(order.paymentToken);
    });

    it('should not allow purchase exceeding round allocation', async function () {
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('200000', GPT_DECIMALS), // More than round allocation
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'ExceedMaxAllocation');
    });

    it('should not allow purchase with insufficient payment token balance', async function () {
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      // burn all user's USDC
      const userBalance = await usdc.balanceOf(user.address);
      await usdc.connect(user).burn(userBalance);

      // amount of USDC needed for the purchase
      const tokenAmount = await salesContract.queryPaymentTokenAmount(
        order.gptAmount,
        await usdc.getAddress(),
      );

      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      )
        .to.be.revertedWithCustomError(salesContract, 'InsufficientBalance')
        .withArgs(await usdc.balanceOf(user.address), tokenAmount);
    });
  });
  describe('Round Management', () => {
    it('should not allow non-sales role to create round', async function () {
      const currentTime = await time.latest();
      await expect(
        salesContract
          .connect(user)
          .createRound(
            ethers.parseUnits('100000', GPT_DECIMALS),
            currentTime,
            currentTime + 24 * 60 * 60,
          ),
      ).to.be.revertedWithCustomError(salesContract, 'SalesRoleNotGranted');
    });

    it('should not allow creating round with end time before start time', async function () {
      const currentTime = await time.latest();
      await expect(
        salesContract
          .connect(sales)
          .createRound(ethers.parseUnits('100000', GPT_DECIMALS), currentTime, currentTime - 1),
      ).to.be.revertedWithCustomError(salesContract, 'InvalidTimeRange');
    });

    it('should not allow creating round with zero tokens', async function () {
      const currentTime = await time.latest();
      await expect(
        salesContract.connect(sales).createRound(0, currentTime, currentTime + 24 * 60 * 60),
      ).to.be.revertedWithCustomError(salesContract, 'InvalidAmount');
    });
  });

  describe('Payment Token Management', () => {
    it('should not allow adding zero address token', async function () {
      await expect(
        salesContract.addAcceptedToken(ethers.ZeroAddress, ethers.ZeroAddress, USDC_DECIMALS),
      ).to.be.revertedWithCustomError(salesContract, 'AddressCannotBeZero');
    });
    it('should accept token correctly', async function () {
      // new mock token
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      const mockToken = await MockERC20Factory.deploy();
      await mockToken.initialize('New Mock', 'NMock', 18);

      // new mock price feed
      const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator');
      const mockPriceFeed = await MockAggregatorFactory.deploy();
      await mockPriceFeed.setPrice(ethers.parseUnits('1', 18));

      await salesContract.addAcceptedToken(
        await mockToken.getAddress(),
        await mockPriceFeed.getAddress(),
        18,
      );

      const tokenInfo = await salesContract.acceptedTokens(await mockToken.getAddress());
      expect(tokenInfo.priceFeed).to.equal(await mockPriceFeed.getAddress());
      expect(tokenInfo.decimals).to.equal(18);
    });
    it('should not allow adding already accepted token', async function () {
      await expect(
        salesContract.addAcceptedToken(
          await usdc.getAddress(),
          await usdcPriceFeed.getAddress(),
          USDC_DECIMALS,
        ),
      ).to.be.revertedWithCustomError(salesContract, 'TokenAlreadyAccepted');
    });

    it('should allow admin to remove accepted token', async function () {
      await salesContract.connect(superAdmin).removeAcceptedToken(await usdc.getAddress());
      const tokenInfo = await salesContract.acceptedTokens(await usdc.getAddress());
      expect(tokenInfo.priceFeed).to.equal(ethers.ZeroAddress);
    });

    it('should not allow non-admin to remove accepted token', async function () {
      await expect(salesContract.connect(user).removeAcceptedToken(await usdc.getAddress()))
        .to.be.revertedWithCustomError(salesContract, 'DefaultAdminRoleNotGranted')
        .withArgs(user.address);
    });
  });
});

// Helper functions
async function getUserDigest(salesContract: SalesContract, signer: SignerWithAddress, order: any) {
  const domain = {
    name: 'GoldPack Token Sales',
    version: '1',
    chainId: (await ethers.provider.getNetwork()).chainId,
    verifyingContract: await salesContract.getAddress(),
  };

  // Match exact USER_ORDER_TYPEHASH from contract
  const types = {
    Order: [
      { name: 'roundId', type: 'uint256' },
      { name: 'buyer', type: 'address' },
      { name: 'gptAmount', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'expiry', type: 'uint256' },
      { name: 'paymentToken', type: 'address' },
    ],
  };

  return await signer.signTypedData(domain, types, order);
}
