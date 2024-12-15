import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import {
  GoldPackToken,
  SalesContract,
  TradingVault,
  MockERC20,
  MockAggregator,
} from '../typechain-types';
import { Wallet } from 'ethers';

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

    // Deploy GoldPackToken
    const GoldPackTokenFactory = await ethers.getContractFactory('GoldPackToken');
    gptToken = (await upgrades.deployProxy(
      GoldPackTokenFactory,
      [superAdmin.address, admin.address, sales.address],
      {
        initializer: 'initialize',
      },
    )) as unknown as GoldPackToken;

    // Deploy TradingVault
    const TradingVaultFactory = await ethers.getContractFactory('TradingVault');
    tradingVault = (await upgrades.deployProxy(
      TradingVaultFactory,
      [safeWallet.address, admin.address, superAdmin.address],
      {
        initializer: 'initialize',
      },
    )) as unknown as TradingVault;

    // Deploy SalesContract
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

    // Setup accepted tokens
    const usdcAddress = await usdc.getAddress();
    const usdcPriceFeedAddress = await usdcPriceFeed.getAddress();

    // Add USDC as accepted token and verify
    await salesContract
      .connect(admin)
      .addAcceptedToken(usdcAddress, usdcPriceFeedAddress, USDC_DECIMALS);

    // Verify USDC is accepted
    const acceptedTokenInfo = await salesContract.acceptedTokens(usdcAddress);
    expect(acceptedTokenInfo.priceFeed).to.equal(usdcPriceFeedAddress);
    expect(acceptedTokenInfo.decimals).to.equal(USDC_DECIMALS);

    // Update price feeds to ensure fresh data
    await updatePriceFeeds();

    // Setup
    await gptToken.grantRole(await gptToken.SALES_ROLE(), await salesContract.getAddress());
  });

  // Add helper function here
  async function updatePriceFeeds() {
    const latestBlock = await ethers.provider.getBlock('latest');
    const currentTimestamp = latestBlock!.timestamp;

    await goldPriceFeed.setRoundData(
      1,
      ethers.parseUnits('2000', 8),
      currentTimestamp,
      currentTimestamp,
      1,
    );

    await usdcPriceFeed.setRoundData(
      1,
      ethers.parseUnits('1', 8),
      currentTimestamp,
      currentTimestamp,
      1,
    );

    return currentTimestamp;
  }

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

  describe('Relayer Signature', async () => {
    it('should update trusted signer correctly', async function () {
      // set a specific relayer
      const relayerPrivateKey =
        '0x72ed06be8eeb542009a55a828f3baffb50252e26774985e93d5abd9f31c216c5';
      const relayerWallet = new ethers.Wallet(relayerPrivateKey, ethers.provider);
      const relayerAddress = await relayerWallet.getAddress();

      // pause the contract before updating the trusted signer
      await salesContract.connect(superAdmin).pause();

      // update the trusted signer
      await salesContract.connect(superAdmin).updateTrustedSigner(relayerAddress);

      // unpause the contract
      await salesContract.connect(superAdmin).unpause();

      expect(await salesContract.trustedSigner()).to.equal(relayerAddress);

      // create round
      const currentTime = await time.latest();
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
      const roundCreatedEvent = receipt.logs.find(
        (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
      );
      if (!roundCreatedEvent) {
        throw new Error('Round creation event not found');
      }
      const parseLog = salesContract.interface.parseLog(roundCreatedEvent);
      const roundId = parseLog?.args[0];

      // Add these lines to mint and approve USDC
      await usdc.mint(user.address, ethers.parseUnits('2000', USDC_DECIMALS));
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('2000', USDC_DECIMALS));

      // create order
      const order = {
        roundId: roundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTime + 5 * 60,
        paymentToken: await usdc.getAddress(),
      };
      console.log('Order:', order);

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayerWallet, order);
      console.log('Relayer Signature:', relayerSignature);

      // set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, roundId);

      await salesContract.connect(user).authorizePurchase({
        ...order,
        userSignature,
        relayerSignature,
      });

      // verify the purchase was successful
      expect(await gptToken.balanceOf(user.address)).to.equal(order.gptAmount);
      expect(await usdc.balanceOf(user.address)).to.equal(0);
      expect(await salesContract.nonces(user.address)).to.equal(1);
    });
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
      await updatePriceFeeds();
      const usdcAddress = await usdc.getAddress();

      // Mint and approve USDC
      await usdc.mint(user.address, ethers.parseUnits('2000', USDC_DECIMALS));
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('2000', USDC_DECIMALS));

      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PreMarketing);

      // Set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PublicSale);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTime + 3600,
        paymentToken: usdcAddress, // Use the verified USDC address
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      order.userSignature = userSignature;

      const relayerSignature = await getUserDigest(salesContract, relayer, order);
      order.relayerSignature = relayerSignature;

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
      await updatePriceFeeds();
      const usdcAddress = await usdc.getAddress();

      // Mint and approve sufficient USDC for multiple purchases
      await usdc.mint(user.address, ethers.parseUnits('4000', USDC_DECIMALS));
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('4000', USDC_DECIMALS));

      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PreMarketing);

      // Set the round to public sale
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);
      expect(await salesContract.RoundStage(currentRoundId)).to.equal(SaleStage.PublicSale);

      // First purchase
      const firstOrder = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('5000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTime + 3600,
        paymentToken: usdcAddress, // Use the verified USDC address
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const firstUserSignature = await getUserDigest(salesContract, user, firstOrder);
      const firstRelayerSignature = await getUserDigest(salesContract, relayer, firstOrder);
      firstOrder.userSignature = firstUserSignature;
      firstOrder.relayerSignature = firstRelayerSignature;

      await salesContract.connect(user).authorizePurchase(firstOrder);

      // Second purchase
      const secondOrder = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('5000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTime + 3600,
        paymentToken: usdcAddress, // Use the verified USDC address
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const secondUserSignature = await getUserDigest(salesContract, user, secondOrder);
      const secondRelayerSignature = await getUserDigest(salesContract, relayer, secondOrder);
      secondOrder.userSignature = secondUserSignature;
      secondOrder.relayerSignature = secondRelayerSignature;

      await salesContract.connect(user).authorizePurchase(secondOrder);

      // Verify user's GPT token balance
      const userBalance = await gptToken.balanceOf(user.address);
      expect(userBalance).to.equal(ethers.parseUnits('10000', GPT_DECIMALS));
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
      const currentTimestamp = await updatePriceFeeds();
      await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTimestamp + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
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

    it('should revert when activating expired round', async function () {
      const currentTime = await time.latest();
      const roundTx = await salesContract.connect(sales).createRound(
        ethers.parseUnits('100000', GPT_DECIMALS),
        currentTime,
        currentTime + 60, // 1 minute duration
      );

      const receipt = await roundTx.wait();
      const log = receipt?.logs.find(
        (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
      );
      const roundId = salesContract.interface.parseLog(log!)?.args[0];

      // Advance time past round end
      await time.increase(120); // 2 minutes

      await expect(
        salesContract.connect(sales).setSaleStage(SaleStage.PublicSale, roundId),
      ).to.be.revertedWithCustomError(salesContract, 'RoundAlreadyEnded');
    });

    it('should track multiple rounds correctly', async function () {
      const currentTime = await time.latest();

      // Create first round
      const round1Tx = await salesContract
        .connect(sales)
        .createRound(ethers.parseUnits('100000', GPT_DECIMALS), currentTime, currentTime + 3600);

      // Create second round
      const round2Tx = await salesContract
        .connect(sales)
        .createRound(
          ethers.parseUnits('200000', GPT_DECIMALS),
          currentTime + 3600,
          currentTime + 7200,
        );

      const [round1Id, round2Id] = await Promise.all([
        round1Tx.wait().then((r) => {
          const log = r?.logs.find(
            (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
          );
          return salesContract.interface.parseLog(log!)?.args[0];
        }),
        round2Tx.wait().then((r) => {
          const log = r?.logs.find(
            (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
          );
          return salesContract.interface.parseLog(log!)?.args[0];
        }),
      ]);

      // Verify rounds are tracked in order
      expect(await salesContract.latestRoundId()).to.equal(round2Id);

      const round1 = await salesContract.rounds(round1Id);
      const round2 = await salesContract.rounds(round2Id);

      expect(round1.maxTokens).to.equal(ethers.parseUnits('100000', GPT_DECIMALS));
      expect(round2.maxTokens).to.equal(ethers.parseUnits('200000', GPT_DECIMALS));
    });
  });

  describe('Payment Token Management', () => {
    it('should not allow adding zero address token', async function () {
      await expect(
        salesContract
          .connect(admin)
          .addAcceptedToken(ethers.ZeroAddress, ethers.ZeroAddress, USDC_DECIMALS),
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

      await salesContract
        .connect(admin)
        .addAcceptedToken(await mockToken.getAddress(), await mockPriceFeed.getAddress(), 18);

      const tokenInfo = await salesContract.acceptedTokens(await mockToken.getAddress());
      expect(tokenInfo.priceFeed).to.equal(await mockPriceFeed.getAddress());
      expect(tokenInfo.decimals).to.equal(18);
    });
    it('should not allow adding already accepted token', async function () {
      // Try to add USDC again (it was already added in beforeEach)
      await expect(
        salesContract
          .connect(admin)
          .addAcceptedToken(
            await usdc.getAddress(),
            await usdcPriceFeed.getAddress(),
            USDC_DECIMALS,
          ),
      )
        .to.be.revertedWithCustomError(salesContract, 'TokenAlreadyAccepted')
        .withArgs(await usdc.getAddress());
    });

    it('should allow admin to remove accepted token', async function () {
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      const newToken = await MockERC20Factory.deploy();
      await newToken.initialize('New Token', 'NEW', 18);

      const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator');
      const newPriceFeed = await MockAggregatorFactory.deploy();

      // First add a new token
      await salesContract
        .connect(admin)
        .addAcceptedToken(await newToken.getAddress(), await newPriceFeed.getAddress(), 18);

      // Then remove it
      await salesContract.connect(admin).removeAcceptedToken(await newToken.getAddress());

      // Verify token is no longer accepted
      const tokenInfo = await salesContract.acceptedTokens(await newToken.getAddress());
      expect(tokenInfo.isAccepted).to.be.false;
    });

    it('should not allow non-admin to remove accepted token', async function () {
      await expect(salesContract.connect(user).removeAcceptedToken(await usdc.getAddress()))
        .to.be.revertedWithCustomError(salesContract, 'AdminRoleNotGranted')
        .withArgs(user.address);
    });
  });

  describe('Pre-Sale Purchase', async () => {
    let currentRoundId: string;
    let currentTime: number;

    beforeEach(async () => {
      currentTime = await time.latest();
      // Create round
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

      const roundCreatedEvent = receipt.logs.find(
        (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
      );

      if (!roundCreatedEvent) {
        throw new Error('Round creation event not found');
      }

      const parseLog = salesContract.interface.parseLog(roundCreatedEvent);
      currentRoundId = parseLog?.args[0];

      // Mint USDC to user
      await usdc.mint(user.address, ethers.parseUnits('2000', USDC_DECIMALS));
      await usdc
        .connect(user)
        .approve(await salesContract.getAddress(), ethers.parseUnits('2000', USDC_DECIMALS));
    });

    it('should process presale purchase successfully for whitelisted user', async function () {
      const currentTimestamp = await updatePriceFeeds();
      await usdc.mint(user.address, ethers.parseUnits('2000', USDC_DECIMALS));

      // Whitelist user and set stage
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: await salesContract.nonces(user.address),
        expiry: currentTimestamp + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      order.userSignature = userSignature;

      const relayerSignature = await getUserDigest(salesContract, relayer, order);
      order.relayerSignature = relayerSignature;

      await salesContract.connect(user).preSalePurchase(order);

      expect(await gptToken.balanceOf(user.address)).to.equal(order.gptAmount);
      expect(await salesContract.nonces(user.address)).to.equal(1);
    });

    it('should revert for non-whitelisted user', async function () {
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'NotWhitelisted');
    });
    it('should revert when not in PreSale stage', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      // Keep in PreMarketing stage

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'RoundStageInvalid');
    });

    it('should revert when buyer address doesnt match sender', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: admin.address, // Different from sender
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, admin, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'BuyerMismatch');
    });

    it('should revert when order is expired', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      // Advance time
      await time.increase(3600); // Advance 1 hour
      const currentTimeNow = await time.latest();

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTimeNow - 60, // Set expiry to 1 minute ago
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'OrderAlreadyExpired');
    });

    it('should revert with insufficient balance', async function () {
      const currentTimestamp = await updatePriceFeeds();
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      // Use existing USDC setup from beforeEach
      const usdcAddress = await usdc.getAddress();

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTimestamp + 3600,
        paymentToken: usdcAddress,
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      // burn all user's USDC
      const userBalance = await usdc.balanceOf(user.address);
      await usdc.connect(user).burn(userBalance);

      const tokenAmount = await salesContract.queryPaymentTokenAmount(order.gptAmount, usdcAddress);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      )
        .to.be.revertedWithCustomError(salesContract, 'InsufficientBalance')
        .withArgs(await usdc.balanceOf(user.address), tokenAmount);
    });

    it('should revert when exceeding max allocation', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('200000', GPT_DECIMALS), // More than round allocation
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'ExceedMaxAllocation');
    });

    it('should revert when round has not started', async function () {
      // Create a future round
      const futureTime = currentTime + 3600; // 1 hour in the future
      const futureRoundTx = await salesContract
        .connect(sales)
        .createRound(
          ethers.parseUnits('100000', GPT_DECIMALS),
          futureTime,
          futureTime + 24 * 60 * 60,
        );
      const receipt = await futureRoundTx.wait();
      if (!receipt) {
        throw new Error('Future round creation failed');
      }

      const roundCreatedEvent = receipt.logs.find(
        (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
      );
      if (!roundCreatedEvent) {
        throw new Error('Round creation event not found');
      }

      const futureRoundId = salesContract.interface.parseLog(roundCreatedEvent)?.args[0];

      await salesContract.connect(sales).addToWhitelist(user.address);
      await expect(
        salesContract.connect(sales).setSaleStage(SaleStage.PreSale, futureRoundId),
      ).to.be.revertedWithCustomError(salesContract, 'RoundNotStarted');

      const order = {
        roundId: futureRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 7200,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'RoundStageInvalid');
    });

    it('should revert when round has ended', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      // Advance time past round end
      await time.increase(25 * 60 * 60); // 25 hours

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 7200,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'RoundAlreadyEnded');
    });

    it('should revert with invalid nonce', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 1, // Invalid nonce (should be 0)
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'InvalidNonce');
    });

    it('should revert when contract is paused', async function () {
      await salesContract.connect(superAdmin).pause();

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'EnforcedPause');
    });

    it('should revert with invalid payment token', async function () {
      await salesContract.connect(sales).addToWhitelist(user.address);
      await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, currentRoundId);

      // Deploy new token that's not accepted
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      const invalidToken = await MockERC20Factory.deploy();
      await invalidToken.initialize('Invalid', 'INV', 18);

      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await invalidToken.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).preSalePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      )
        .to.be.revertedWithCustomError(salesContract, 'TokenNotAccepted')
        .withArgs(await invalidToken.getAddress());
    });
  });

  describe('Token Management', () => {
    it('should add accepted token correctly', async function () {
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      const newToken = await MockERC20Factory.deploy();
      await newToken.initialize('New Token', 'NEW', 18);

      const MockAggregatorFactory = await ethers.getContractFactory('MockAggregator');
      const newPriceFeed = await MockAggregatorFactory.deploy();

      await salesContract
        .connect(admin)
        .addAcceptedToken(await newToken.getAddress(), await newPriceFeed.getAddress(), 18);

      const tokenInfo = await salesContract.acceptedTokens(await newToken.getAddress());
      expect(tokenInfo.isAccepted).to.be.true;
      expect(tokenInfo.decimals).to.equal(18);
    });

    it('should revert when non-admin adds token', async function () {
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      const newToken = await MockERC20Factory.deploy();
      await newToken.initialize('New Token', 'NEW', 18);

      await expect(
        salesContract
          .connect(user)
          .addAcceptedToken(await newToken.getAddress(), await usdcPriceFeed.getAddress(), 18),
      )
        .to.be.revertedWithCustomError(salesContract, 'AdminRoleNotGranted')
        .withArgs(user.address);
    });
  });

  describe('Price Calculations', () => {
    it('should calculate payment amounts correctly with different decimals', async function () {
      await updatePriceFeeds();

      // Use existing USDC setup from beforeEach instead of adding it again
      const usdcAddress = await usdc.getAddress();

      const gptAmount = ethers.parseUnits('10000', GPT_DECIMALS);
      const paymentAmount = await salesContract.queryPaymentTokenAmount(gptAmount, usdcAddress);

      // Expected: (2000 * 10000) / 10000 = 2000 USDC
      expect(paymentAmount).to.equal(ethers.parseUnits('2000', USDC_DECIMALS));
    });
  });

  describe('Emergency Functions', () => {
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

    it('should prevent purchases when paused', async function () {
      // Pause the contract using superAdmin
      await salesContract.connect(superAdmin).pause();
      expect(await salesContract.paused()).to.be.true;

      // Try to purchase when paused
      const order = {
        roundId: currentRoundId,
        buyer: user.address,
        gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
        nonce: 0,
        expiry: currentTime + 3600,
        paymentToken: await usdc.getAddress(),
        userSignature: '0x00',
        relayerSignature: '0x00',
      };

      const userSignature = await getUserDigest(salesContract, user, order);
      const relayerSignature = await getUserDigest(salesContract, relayer, order);

      await expect(
        salesContract.connect(user).authorizePurchase({
          ...order,
          userSignature,
          relayerSignature,
        }),
      ).to.be.revertedWithCustomError(salesContract, 'EnforcedPause');
    });
  });

  describe('Recovery Functions', () => {
    let mockToken: MockERC20;

    beforeEach(async () => {
      // Deploy mock token
      const MockERC20Factory = await ethers.getContractFactory('MockERC20');
      mockToken = await MockERC20Factory.deploy();
      await mockToken.initialize('Mock', 'MCK', 18);

      // Mint tokens to sales contract
      await mockToken.mint(await salesContract.getAddress(), ethers.parseUnits('1000', 18));
    });

    it('should successfully recover ERC20 tokens', async function () {
      // Mint some tokens to the contract
      await usdc.mint(await salesContract.getAddress(), 1000);
      const initialBalance = await usdc.balanceOf(superAdmin.address);

      // Recover tokens using superAdmin
      await salesContract.connect(superAdmin).recoverERC20(await usdc.getAddress(), 1000);

      // Verify balance changes
      expect(await usdc.balanceOf(superAdmin.address)).to.equal(initialBalance + BigInt(1000));
    });

    it('should revert if caller is not admin', async function () {
      await expect(salesContract.connect(user).recoverERC20(await usdc.getAddress(), 100))
        .to.be.revertedWithCustomError(salesContract, 'DefaultAdminRoleNotGranted')
        .withArgs(user.address);
    });

    it('should revert when trying to recover GPT token', async function () {
      await expect(
        salesContract.connect(superAdmin).recoverERC20(await gptToken.getAddress(), 100),
      ).to.be.revertedWithCustomError(salesContract, 'CannotRecoverGptToken');
    });

    it('should revert when amount is zero', async function () {
      await expect(
        salesContract.connect(superAdmin).recoverERC20(await usdc.getAddress(), 0),
      ).to.be.revertedWithCustomError(salesContract, 'InvalidAmount');
    });

    it('should revert when contract balance is insufficient', async function () {
      await expect(
        salesContract.connect(superAdmin).recoverERC20(await usdc.getAddress(), 100000),
      ).to.be.revertedWithCustomError(salesContract, 'InsufficientBalance');
    });
  });

  describe('Whitelist Management', () => {
    let whitelistedUser: SignerWithAddress;

    beforeEach(async () => {
      whitelistedUser = await ethers.provider.getSigner(10);
      // Add user to whitelist first
      await salesContract.connect(sales).addToWhitelist(whitelistedUser.address);
    });

    describe('removeFromWhitelist', () => {
      it('should successfully remove an address from whitelist', async () => {
        // Verify user is whitelisted
        expect(await salesContract.whitelistedAddresses(whitelistedUser.address)).to.be.true;

        // Remove from whitelist
        await expect(salesContract.connect(sales).removeFromWhitelist(whitelistedUser.address))
          .to.emit(salesContract, 'AddressRemoved')
          .withArgs(whitelistedUser.address);

        // Verify user is no longer whitelisted
        expect(await salesContract.whitelistedAddresses(whitelistedUser.address)).to.be.false;
      });

      it('should revert when caller does not have SALES_ROLE', async () => {
        await expect(salesContract.connect(user).removeFromWhitelist(whitelistedUser.address))
          .to.be.revertedWithCustomError(salesContract, 'SalesRoleNotGranted')
          .withArgs(user.address);
      });

      it('should revert when trying to remove zero address', async () => {
        await expect(
          salesContract.connect(sales).removeFromWhitelist(ethers.ZeroAddress),
        ).to.be.revertedWithCustomError(salesContract, 'AddressCannotBeZero');
      });

      it('should revert when address is not whitelisted', async () => {
        const nonWhitelistedUser = await ethers.provider.getSigner(11);

        await expect(salesContract.connect(sales).removeFromWhitelist(nonWhitelistedUser.address))
          .to.be.revertedWithCustomError(salesContract, 'AddressNotWhitelisted')
          .withArgs(nonWhitelistedUser.address);
      });

      it('should not allow removed address to participate in presale', async () => {
        // Remove from whitelist
        await salesContract.connect(sales).removeFromWhitelist(whitelistedUser.address);

        // Create a round
        const currentTime = await time.latest();
        const roundTx = await salesContract
          .connect(sales)
          .createRound(
            ethers.parseUnits('100000', GPT_DECIMALS),
            currentTime,
            currentTime + 24 * 60 * 60,
          );

        const receipt = await roundTx.wait();
        const roundCreatedEvent = receipt?.logs.find(
          (log) => salesContract.interface.parseLog(log)?.name === 'RoundCreated',
        );
        const roundId = salesContract.interface.parseLog(roundCreatedEvent!)?.args[0];

        // Set to PreSale stage
        await salesContract.connect(sales).setSaleStage(SaleStage.PreSale, roundId);

        // Attempt presale purchase
        const order = {
          roundId: roundId,
          buyer: whitelistedUser.address,
          gptAmount: ethers.parseUnits('10000', GPT_DECIMALS),
          nonce: await salesContract.nonces(whitelistedUser.address),
          expiry: currentTime + 3600,
          paymentToken: await usdc.getAddress(),
          userSignature: '0x00',
          relayerSignature: '0x00',
        };

        const userSignature = await getUserDigest(salesContract, whitelistedUser, order);
        const relayerSignature = await getUserDigest(salesContract, relayer, order);
        order.userSignature = userSignature;
        order.relayerSignature = relayerSignature;

        await expect(
          salesContract.connect(whitelistedUser).preSalePurchase(order),
        ).to.be.revertedWithCustomError(salesContract, 'NotWhitelisted');
      });

      it('should allow re-adding a previously removed address', async () => {
        // Remove from whitelist
        await salesContract.connect(sales).removeFromWhitelist(whitelistedUser.address);
        expect(await salesContract.whitelistedAddresses(whitelistedUser.address)).to.be.false;

        // Re-add to whitelist
        await salesContract.connect(sales).addToWhitelist(whitelistedUser.address);
        expect(await salesContract.whitelistedAddresses(whitelistedUser.address)).to.be.true;
      });
    });
  });
});

// Helper functions
async function getUserDigest(
  salesContract: SalesContract,
  signer: SignerWithAddress | Wallet,
  order: any,
) {
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
