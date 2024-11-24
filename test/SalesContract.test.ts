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
  NotStarted,
  PrivateSale,
  PublicSale,
  Ended,
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
    await salesContract.connect(sales).setSaleStage(SaleStage.PublicSale); // PublicSale
  });

  it('should set up contracts correctly', async function () {
    expect(await gptToken.getAddress()).to.equal(await salesContract.gptToken());
    expect(await goldPriceFeed.getAddress()).to.equal(await salesContract.goldPriceFeed());
    expect(await tradingVault.getAddress()).to.equal(await salesContract.tradingVault());
    expect(await salesContract.currentStage()).to.equal(SaleStage.PublicSale);
    expect(await salesContract.DOMAIN_SEPARATOR()).to.not.equal(ethers.ZeroAddress);
    expect(await salesContract.trustedSigner()).to.equal(relayer.address);
    expect(await salesContract.connect(admin).acceptedTokens(await usdc.getAddress())).to.not.equal(
      ethers.ZeroAddress,
    );
    expect(await salesContract.trustedSigner()).to.equal(relayer.address);
  });

  describe('authorize purchase', async () => {
    it('should authorize purchase successfully', async function () {
      // Mint USDC to user
      await usdc.mint(user.address, ethers.parseUnits('2000', 6));

      const currentTime = await time.latest();

      // check the public sale stage
      expect(await salesContract.currentStage()).to.equal(SaleStage.PublicSale);
      // Create and activate round
      const createdRoundTx = await salesContract
        .connect(sales)
        .createRound(ethers.parseUnits('100000', 6), currentTime, currentTime + 86400);
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
      const currentRoundId = parseLog?.args[0];

      await salesContract.connect(sales).activateRound(currentRoundId);

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

      // Verify results
      expect(await gptToken.balanceOf(user.address)).to.equal(order.gptAmount);
      expect(await usdc.balanceOf(user.address)).to.equal(0);
      expect(await salesContract.nonces(user.address)).to.equal(1);
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
