import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { RewardDistribution, MockERC20, RewardDistributionV2 } from '../typechain-types';

describe('RewardDistribution Tests', function () {
  // Constants
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;
  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes('ADMIN_ROLE'));

  // Contract instances
  let rewardToken1: MockERC20;
  let rewardToken2: MockERC20;
  let rewardDistribution: RewardDistribution;

  // Signers
  let superAdmin: SignerWithAddress;
  let admin: SignerWithAddress;
  let nonAdmin: SignerWithAddress;
  let shareholder1: SignerWithAddress;
  let shareholder2: SignerWithAddress;
  // let anotherAdmin: SignerWithAddress;
  // let newSuperAdmin: SignerWithAddress;

  beforeEach(async function () {
    // Get signers
    [superAdmin, admin, shareholder1, shareholder2, nonAdmin] = await ethers.getSigners();

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    rewardToken1 = await MockERC20Factory.deploy();
    await rewardToken1.initialize('Reward Token 1', 'RT1', 18);

    rewardToken2 = await MockERC20Factory.deploy();
    await rewardToken2.initialize('Reward Token 2', 'RT2', 18);

    // Deploy RewardDistribution with proxy and deployer as super admin
    const RewardDistributionFactory = await ethers.getContractFactory(
      'RewardDistribution',
      superAdmin,
    );
    rewardDistribution = (await upgrades.deployProxy(
      RewardDistributionFactory,
      [superAdmin.address, admin.address],
      {
        initializer: 'initialize',
      },
    )) as unknown as RewardDistribution;
  });

  describe('Initialization', () => {
    it('should initialize successfully', async function () {
      expect(await rewardDistribution.hasRole(DEFAULT_ADMIN_ROLE, superAdmin.address)).to.be.true;
      expect(await rewardDistribution.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
      expect(await rewardDistribution.totalShares()).to.equal(0);
    });

    it('should initialize with correct roles', async () => {
      expect(await rewardDistribution.hasRole(DEFAULT_ADMIN_ROLE, superAdmin)).to.be.true;
      expect(await rewardDistribution.hasRole(ADMIN_ROLE, admin)).to.be.true;
    });

    it('should revert with zero super admin address', async function () {
      const RewardDistributionFactory = await ethers.getContractFactory('RewardDistribution');
      await expect(
        upgrades.deployProxy(RewardDistributionFactory, [ethers.ZeroAddress, admin.address], {
          initializer: 'initialize',
        }),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AddressCannotBeZero');
    });

    it('should revert with zero admin address', async function () {
      const RewardDistributionFactory = await ethers.getContractFactory('RewardDistribution');
      await expect(
        upgrades.deployProxy(RewardDistributionFactory, [superAdmin.address, ethers.ZeroAddress], {
          initializer: 'initialize',
        }),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AddressCannotBeZero');
    });

    it('should revert on reinitialization', async function () {
      await expect(
        rewardDistribution.initialize(superAdmin.address, admin.address),
      ).to.be.revertedWithCustomError(rewardDistribution, 'InvalidInitialization');
    });
  });

  describe('Share Allocation', () => {
    it('should allocate shares successfully', async function () {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));

      const [shares, isLocked, isActivated] = await rewardDistribution.getShareholders(
        shareholder1.address,
      );
      expect(shares).to.equal(ethers.parseUnits('0.5', 18));
      expect(isLocked).to.be.false;
      expect(isActivated).to.be.true;
      expect(await rewardDistribution.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    });

    it('should revert when exceeding scale', async function () {
      await expect(
        rewardDistribution
          .connect(admin)
          .setShares(shareholder1.address, ethers.parseUnits('2', 18)),
      ).to.be.revertedWithCustomError(rewardDistribution, 'TotalSharesExceedMaximum');
    });

    it('should revert with zero address', async function () {
      await expect(
        rewardDistribution.connect(admin).setShares(ethers.ZeroAddress, ethers.parseUnits('1', 18)),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AddressCannotBeZero');
    });

    it('should revert when paused', async function () {
      await rewardDistribution.connect(superAdmin).pause();
      await expect(
        rewardDistribution
          .connect(admin)
          .setShares(shareholder1.address, ethers.parseUnits('100', 18)),
      ).to.be.revertedWithCustomError(rewardDistribution, 'EnforcedPause');
    });
  });

  describe('Claim All Rewards', () => {
    let distributionId1: string;
    let distributionId2: string;
    beforeEach(async () => {
      // Setup
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken2.getAddress());

      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));
      await rewardToken2.mint(await rewardDistribution.getAddress(), ethers.parseUnits('2000', 18));

      const currentTime = await time.latest();
      const tx1 = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken1.getAddress(),
          ethers.parseUnits('1000', 18),
          currentTime + 100,
        );

      const receipt = await tx1.wait();

      if (!receipt) {
        throw new Error('Distribution creation failed');
      }

      // retrieve distributionId from event
      const distributionCreatedEvent = receipt.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );

      if (!distributionCreatedEvent) {
        throw new Error('Distribution creation event not found');
      }

      const parseLog = rewardDistribution.interface.parseLog(distributionCreatedEvent);
      distributionId1 = parseLog?.args[0];

      const tx2 = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken2.getAddress(),
          ethers.parseUnits('2000', 18),
          currentTime + 200,
        );

      const receipt2 = await tx2.wait();

      if (!receipt2) {
        throw new Error('Distribution creation failed');
      }

      // retrieve distributionId from event
      const distributionCreatedEvent2 = receipt2.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );

      if (!distributionCreatedEvent2) {
        throw new Error('Distribution creation event not found');
      }

      const parseLog2 = rewardDistribution.interface.parseLog(distributionCreatedEvent2);
      distributionId2 = parseLog2?.args[0];

      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
    });

    it('should claim all rewards successfully', async () => {
      await time.increase(201);

      await expect(rewardDistribution.connect(shareholder1).claimAllRewards())
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('500', 18),
          await rewardToken1.getAddress(),
          distributionId1,
        )
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('1000', 18),
          await rewardToken2.getAddress(),
          distributionId2,
        );

      expect(await rewardToken1.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('500', 18),
      );
      expect(await rewardToken2.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('1000', 18),
      );
    });

    it('should revert claiming when locked', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));

      await rewardDistribution.connect(admin).lockRewards(shareholder1.address);
      await time.increase(101);

      const [shares, isLocked, isActivated] = await rewardDistribution.getShareholders(
        shareholder1.address,
      );

      expect(shares).to.equal(ethers.parseUnits('0.5', 18));
      expect(isLocked).to.be.true;
      expect(isActivated).to.be.true;

      await expect(rewardDistribution.connect(shareholder1).claimAllRewards())
        .to.be.revertedWithCustomError(rewardDistribution, 'ShareholderLocked')
        .withArgs(shareholder1.address);
    });
  });

  describe('Lock/Unlock Rewards', () => {
    it('should lock rewards successfully', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));

      await expect(rewardDistribution.connect(admin).lockRewards(shareholder1.address))
        .to.emit(rewardDistribution, 'RewardsLocked')
        .withArgs(shareholder1.address);

      const [shares, isLocked, isActivated] = await rewardDistribution.getShareholders(
        shareholder1.address,
      );
      expect(shares).to.equal(ethers.parseUnits('0.5', 18));
      expect(isLocked).to.be.true;
      expect(isActivated).to.be.true;
    });

    it('should revert when locking already locked rewards', async () => {
      await rewardDistribution.connect(admin).lockRewards(shareholder1.address);

      await expect(
        rewardDistribution.connect(admin).lockRewards(shareholder1.address),
      ).to.be.revertedWithCustomError(rewardDistribution, 'RewardsAlreadyLocked');
    });

    it('should unlock rewards successfully', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
      await rewardDistribution.connect(admin).lockRewards(shareholder1.address);

      await expect(rewardDistribution.connect(admin).unlockRewards(shareholder1.address))
        .to.emit(rewardDistribution, 'RewardsUnlocked')
        .withArgs(shareholder1.address);

      const [shares, isLocked] = await rewardDistribution.getShareholders(shareholder1.address);
      expect(shares).to.equal(ethers.parseUnits('0.5', 18));
      expect(isLocked).to.be.false;
    });

    it('should revert when unlocking non-locked rewards', async () => {
      await expect(
        rewardDistribution.connect(admin).unlockRewards(shareholder1.address),
      ).to.be.revertedWithCustomError(rewardDistribution, 'RewardsNotLocked');
    });

    it('should revert when non-admin tries to lock rewards', async function () {
      await expect(rewardDistribution.connect(nonAdmin).lockRewards(shareholder1.address))
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });

    it('should revert when non-admin tries to unlock rewards', async function () {
      await expect(rewardDistribution.connect(nonAdmin).unlockRewards(shareholder1.address))
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });
  });
  describe('Update Shareholder Shares', () => {
    it('should update shares successfully', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.8', 18));

      const [shares, ,] = await rewardDistribution.getShareholders(shareholder1.address);
      expect(shares).to.equal(ethers.parseUnits('0.8', 18));
    });

    it('should revert when exceeding scale', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.9', 18));

      await expect(
        rewardDistribution
          .connect(admin)
          .setShares(shareholder1.address, ethers.parseUnits('1.1', 18)),
      ).to.be.revertedWithCustomError(rewardDistribution, 'TotalSharesExceedMaximum');
    });

    it('should remove shareholder when updating to zero shares', async () => {
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));

      await rewardDistribution.connect(admin).setShares(shareholder1.address, 0);

      const [shares, ,] = await rewardDistribution.getShareholders(shareholder1.address);
      expect(shares).to.equal(0);
      expect(await rewardDistribution.hasRole(ADMIN_ROLE, shareholder1.address)).to.be.false;
    });

    it('should revert with zero address', async () => {
      await expect(
        rewardDistribution
          .connect(admin)
          .setShares(ethers.ZeroAddress, ethers.parseUnits('0.1', 18)),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AddressCannotBeZero');
    });
  });

  describe('Reward Token Management', () => {
    it('should add reward token successfully', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());

      expect(await rewardDistribution.supportTokens(await rewardToken1.getAddress())).to.be.true;
      expect(await rewardDistribution.isRewardToken(await rewardToken1.getAddress())).to.be.true;
    });

    it('should revert when adding already supported token', async function () {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await expect(
        rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress()),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'TokenAlreadyAccepted')
        .withArgs(await rewardToken1.getAddress());
    });

    it('should revert when adding zero address token', async function () {
      await expect(
        rewardDistribution.connect(admin).addRewardToken(ethers.ZeroAddress),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AddressCannotBeZero');
    });

    it('should revert when non-admin adds token', async function () {
      await expect(
        rewardDistribution.connect(nonAdmin).addRewardToken(await rewardToken1.getAddress()),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });

    it('should remove reward token successfully', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardDistribution.connect(admin).removeRewardToken(await rewardToken1.getAddress());

      expect(await rewardDistribution.supportTokens(await rewardToken1.getAddress())).to.be.false;
      expect(await rewardDistribution.isRewardToken(await rewardToken1.getAddress())).to.be.false;
    });
  });

  describe('Top Up Rewards', () => {
    it('should top up rewards successfully', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(admin.address, ethers.parseUnits('1000', 18));
      await rewardToken1
        .connect(admin)
        .approve(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      await rewardDistribution
        .connect(admin)
        .topUpRewards(ethers.parseUnits('500', 18), await rewardToken1.getAddress());

      expect(await rewardToken1.balanceOf(await rewardDistribution.getAddress())).to.equal(
        ethers.parseUnits('500', 18),
      );
    });

    it('should revert when topping up with zero amount', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());

      await expect(
        rewardDistribution.connect(admin).topUpRewards(0, await rewardToken1.getAddress()),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AmountCannotBeZero');
    });

    it('should revert when topping up unsupported token', async () => {
      await expect(
        rewardDistribution
          .connect(admin)
          .topUpRewards(ethers.parseUnits('100', 18), await rewardToken1.getAddress()),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'TokenNotAccepted')
        .withArgs(await rewardToken1.getAddress());
    });

    it('should revert when contract is paused', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(admin.address, ethers.parseUnits('1000', 18));
      await rewardToken1
        .connect(admin)
        .approve(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));
      await rewardDistribution.connect(superAdmin).pause();

      await expect(
        rewardDistribution
          .connect(admin)
          .topUpRewards(ethers.parseUnits('500', 18), await rewardToken1.getAddress()),
      ).to.be.revertedWithCustomError(rewardDistribution, 'EnforcedPause');
    });

    it('should revert when non-admin tops up', async () => {
      await expect(
        rewardDistribution
          .connect(nonAdmin)
          .topUpRewards(ethers.parseUnits('100', 18), await rewardToken1.getAddress()),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });
  });

  describe('Claim Reward', () => {
    let distributionId: string;

    beforeEach(async () => {
      // Setup
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      // Create distribution
      const currentTime = await time.latest();
      const distributionTime = currentTime + 100;

      const tx = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken1.getAddress(),
          ethers.parseUnits('1000', 18),
          distributionTime,
        );

      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error('Distribution creation failed');
      }

      // Retrieve distributionId from event
      const distributionCreatedEvent = receipt.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );

      if (!distributionCreatedEvent) {
        throw new Error('Distribution creation event not found');
      }

      const parseLog = rewardDistribution.interface.parseLog(distributionCreatedEvent);
      distributionId = parseLog?.args[0];

      // Allocate shares
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder2.address, ethers.parseUnits('0.5', 18));
    });

    it('should claim reward successfully', async () => {
      // Fast-forward time
      await time.increase(101);

      // Claim reward
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId))
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('500', 18),
          await rewardToken1.getAddress(),
          distributionId,
        );

      // Verify reward balance
      expect(await rewardToken1.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('500', 18),
      );
    });

    it('should revert when claiming before distribution time', async () => {
      // Attempt to claim before distribution time
      await expect(
        rewardDistribution.connect(shareholder1).claimReward(distributionId),
      ).to.be.revertedWithCustomError(rewardDistribution, 'RewardsNotYetClaimable');
    });

    it('should revert when claiming already claimed rewards', async () => {
      // Fast-forward time and claim
      await time.increase(101);
      await rewardDistribution.connect(shareholder1).claimReward(distributionId);

      // Attempt to claim again
      await expect(
        rewardDistribution.connect(shareholder1).claimReward(distributionId),
      ).to.be.revertedWithCustomError(rewardDistribution, 'RewardsAlreadyClaimed');
    });

    it('should revert when claiming with locked rewards', async () => {
      // Lock rewards
      await rewardDistribution.connect(admin).lockRewards(shareholder1.address);

      // Fast-forward time
      await time.increase(101);

      // Attempt to claim
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'ShareholderLocked')
        .withArgs(shareholder1.address);
    });

    it('should revert when claiming with no shares', async () => {
      // Remove shares
      await rewardDistribution.connect(admin).setShares(shareholder1.address, 0);

      // Fast-forward time
      await time.increase(101);

      // Attempt to claim
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'ShareholderNotActivated')
        .withArgs(shareholder1.address);
    });

    it('should revert when claiming with non-activated shareholder', async () => {
      // Fast-forward time
      await time.increase(101);

      // Attempt to claim with non-activated address
      await expect(rewardDistribution.connect(nonAdmin).claimReward(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'ShareholderNotActivated')
        .withArgs(nonAdmin.address);
    });
  });

  describe('Create Distribution', () => {
    it('should create distribution successfully', async () => {
      // Setup
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      const distributionTime = (await time.latest()) + 100;

      // Create distribution and get the event
      const tx = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken1.getAddress(),
          ethers.parseUnits('1000', 18),
          distributionTime,
        );

      // Wait for the transaction to be mined
      const receipt = await tx.wait();

      // Get the distributionId from the event
      const distributionCreatedEvent = receipt?.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );

      if (!distributionCreatedEvent) {
        throw new Error('Distribution creation event not found');
      }

      const parsedLog = rewardDistribution.interface.parseLog(distributionCreatedEvent);
      const distributionId = parsedLog?.args[0];

      // Verify distribution details using the ID from the event
      const [rewardToken, totalRewards, storedDistributionTime] =
        await rewardDistribution.getDistribution(distributionId);

      expect(rewardToken).to.equal(await rewardToken1.getAddress());
      expect(totalRewards).to.equal(ethers.parseUnits('1000', 18));
      expect(storedDistributionTime).to.equal(distributionTime);
    });

    it('should revert with zero rewards', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());

      await expect(
        rewardDistribution
          .connect(admin)
          .createDistribution(await rewardToken1.getAddress(), 0, (await time.latest()) + 100),
      ).to.be.revertedWithCustomError(rewardDistribution, 'AmountCannotBeZero');
    });

    it('should revert with past distribution time', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      await expect(
        rewardDistribution
          .connect(admin)
          .createDistribution(
            await rewardToken1.getAddress(),
            ethers.parseUnits('500', 18),
            (await time.latest()) - 10,
          ),
      ).to.be.revertedWithCustomError(rewardDistribution, 'InvalidTimeRange');
    });

    it('should revert with insufficient funds', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('500', 18));

      await expect(
        rewardDistribution
          .connect(admin)
          .createDistribution(
            await rewardToken1.getAddress(),
            ethers.parseUnits('1000', 18),
            (await time.latest()) + 100,
          ),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'InsufficientBalance')
        .withArgs(ethers.parseUnits('500', 18), ethers.parseUnits('1000', 18));
    });

    it('should revert when paused', async () => {
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));
      await rewardDistribution.connect(superAdmin).pause();

      await expect(
        rewardDistribution
          .connect(admin)
          .createDistribution(
            await rewardToken1.getAddress(),
            ethers.parseUnits('500', 18),
            (await time.latest()) + 100,
          ),
      ).to.be.revertedWithCustomError(rewardDistribution, 'EnforcedPause');
    });

    it('should revert when called by non-admin', async () => {
      await expect(
        rewardDistribution
          .connect(nonAdmin)
          .createDistribution(
            await rewardToken1.getAddress(),
            ethers.parseUnits('500', 18),
            (await time.latest()) + 100,
          ),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });
  });

  describe('Pause/Unpause', () => {
    it('should pause successfully', async () => {
      await expect(rewardDistribution.connect(superAdmin).pause())
        .to.emit(rewardDistribution, 'Paused')
        .withArgs(superAdmin.address);

      expect(await rewardDistribution.paused()).to.be.true;
    });

    it('should revert when non-default-admin tries to pause', async () => {
      await expect(rewardDistribution.connect(admin).pause())
        .to.be.revertedWithCustomError(rewardDistribution, 'DefaultAdminRoleNotGranted')
        .withArgs(admin.address);
    });

    it('should unpause successfully', async () => {
      // First, pause the contract
      await rewardDistribution.connect(superAdmin).pause();

      // Then unpause and check event
      await expect(rewardDistribution.connect(superAdmin).unpause())
        .to.emit(rewardDistribution, 'Unpaused')
        .withArgs(superAdmin.address);

      expect(await rewardDistribution.paused()).to.be.false;
    });

    it('should revert when non-default-admin tries to unpause', async () => {
      // First, pause the contract
      await rewardDistribution.connect(superAdmin).pause();

      // Attempt to unpause by non-default-admin
      await expect(rewardDistribution.connect(admin).unpause())
        .to.be.revertedWithCustomError(rewardDistribution, 'DefaultAdminRoleNotGranted')
        .withArgs(admin.address);
    });
  });
  describe('Upgradeability', () => {
    it('should upgrade to V2 successfully', async () => {
      const RewardDistributionV2Factory = await ethers.getContractFactory(
        'RewardDistributionV2',
        superAdmin,
      );
      const upgraded = (await upgrades.upgradeProxy(
        await rewardDistribution.getAddress(),
        RewardDistributionV2Factory.connect(superAdmin),
      )) as unknown as RewardDistributionV2;

      // Test new V2 functionality
      await upgraded.setNewVariable(12345);
      expect(await upgraded.getNewVariable()).to.equal(12345);
    });

    it('should revert upgrade when called by non-admin', async () => {
      const RewardDistributionV2Factory = await ethers.getContractFactory('RewardDistributionV2');
      await expect(
        upgrades.upgradeProxy(
          await rewardDistribution.getAddress(),
          RewardDistributionV2Factory.connect(nonAdmin),
        ),
      )
        .to.be.revertedWithCustomError(rewardDistribution, 'DefaultAdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });
  });

  describe('Finalize Distribution', () => {
    let distributionId: string;

    beforeEach(async () => {
      // Setup
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      // Create distribution
      const currentTime = await time.latest();
      const tx = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken1.getAddress(),
          ethers.parseUnits('1000', 18),
          currentTime + 100,
        );

      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error('Distribution creation failed');
      }

      // Get distributionId from event
      const distributionCreatedEvent = receipt.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );

      if (!distributionCreatedEvent) {
        throw new Error('Distribution creation event not found');
      }

      const parseLog = rewardDistribution.interface.parseLog(distributionCreatedEvent);
      distributionId = parseLog?.args[0];

      // Setup shareholders
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder2.address, ethers.parseUnits('0.5', 18));
    });

    it('should finalize distribution after all rewards claimed', async () => {
      // Fast-forward time
      await time.increase(101);

      // Both shareholders claim their rewards
      await rewardDistribution.connect(shareholder1).claimReward(distributionId);
      await rewardDistribution.connect(shareholder2).claimReward(distributionId);

      // Finalize distribution
      await expect(rewardDistribution.connect(admin).finalizeDistribution(distributionId))
        .to.emit(rewardDistribution, 'DistributionFinalized')
        .withArgs(distributionId);

      // Verify distribution is finalized
      const distribution = await rewardDistribution.distributions(distributionId);
      expect(distribution.finalized).to.be.true;
    });

    it('should revert when not all rewards are claimed', async () => {
      // Fast-forward time
      await time.increase(101);

      // Only one shareholder claims rewards
      await rewardDistribution.connect(shareholder1).claimReward(distributionId);

      await expect(rewardDistribution.connect(admin).finalizeDistribution(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'NotAllRewardsClaimed')
        .withArgs(distributionId);
    });

    it('should revert when distribution is already finalized', async () => {
      // Fast-forward time
      await time.increase(101);

      // Both shareholders claim their rewards
      await rewardDistribution.connect(shareholder1).claimReward(distributionId);
      await rewardDistribution.connect(shareholder2).claimReward(distributionId);

      // Finalize distribution
      await rewardDistribution.connect(admin).finalizeDistribution(distributionId);

      // Try to finalize again
      await expect(rewardDistribution.connect(admin).finalizeDistribution(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'DistributionFinalized')
        .withArgs(distributionId);
    });

    it('should revert when called by non-admin', async () => {
      await expect(rewardDistribution.connect(nonAdmin).finalizeDistribution(distributionId))
        .to.be.revertedWithCustomError(rewardDistribution, 'AdminRoleNotGranted')
        .withArgs(nonAdmin.address);
    });
  });

  describe('Edge Cases', () => {
    let distributionId1: string;
    let distributionId2: string;

    beforeEach(async () => {
      // Setup reward tokens
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken1.getAddress());
      await rewardDistribution.connect(admin).addRewardToken(await rewardToken2.getAddress());

      // Mint tokens to contract
      await rewardToken1.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));
      await rewardToken2.mint(await rewardDistribution.getAddress(), ethers.parseUnits('1000', 18));

      // Create distributions
      const currentTime = await time.latest();

      // First distribution with token1
      const tx1 = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken1.getAddress(),
          ethers.parseUnits('500', 18),
          currentTime + 100,
        );
      const receipt1 = await tx1.wait();
      const event1 = receipt1?.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );
      distributionId1 = rewardDistribution.interface.parseLog(event1!)?.args[0];

      // Second distribution with token2
      const tx2 = await rewardDistribution
        .connect(admin)
        .createDistribution(
          await rewardToken2.getAddress(),
          ethers.parseUnits('500', 18),
          currentTime + 200,
        );
      const receipt2 = await tx2.wait();
      const event2 = receipt2?.logs.find(
        (log) => rewardDistribution.interface.parseLog(log)?.name === 'RewardsDistributed',
      );
      distributionId2 = rewardDistribution.interface.parseLog(event2!)?.args[0];

      // Setup initial shares
      await rewardDistribution
        .connect(admin)
        .setShares(shareholder1.address, ethers.parseUnits('0.5', 18));
    });

    it('should handle setting shares to zero for active shareholder', async () => {
      // Verify initial state
      const [initialShares, , isActivated] = await rewardDistribution.getShareholders(
        shareholder1.address,
      );
      expect(initialShares).to.equal(ethers.parseUnits('0.5', 18));
      expect(isActivated).to.be.true;

      // Set shares to zero
      await rewardDistribution.connect(admin).setShares(shareholder1.address, 0);

      // Verify shareholder is deactivated
      const [finalShares, , isStillActivated] = await rewardDistribution.getShareholders(
        shareholder1.address,
      );
      expect(finalShares).to.equal(0);
      expect(isStillActivated).to.be.false;

      // Fast forward and try to claim rewards
      await time.increase(101);
      await expect(
        rewardDistribution.connect(shareholder1).claimReward(distributionId1),
      ).to.be.revertedWithCustomError(rewardDistribution, 'ShareholderNotActivated');
    });

    it('should handle locking and unlocking rewards mid-distribution', async () => {
      // Fast forward to distribution time
      await time.increase(101);

      // Lock rewards
      await rewardDistribution.connect(admin).lockRewards(shareholder1.address);

      // Try to claim while locked
      await expect(
        rewardDistribution.connect(shareholder1).claimReward(distributionId1),
      ).to.be.revertedWithCustomError(rewardDistribution, 'ShareholderLocked');

      // Unlock rewards
      await rewardDistribution.connect(admin).unlockRewards(shareholder1.address);

      // Should now be able to claim
      // Shareholder1 has 50% shares, so they get 50% of the rewards (250 tokens)
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId1))
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('250', 18), // Changed from 500 to 250
          await rewardToken1.getAddress(),
          distributionId1,
        );
    });

    it('should handle multiple active distributions with different tokens', async () => {
      await time.increase(201); // Fast forward past both distribution times

      // Claim from first distribution
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId1))
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('250', 18),
          await rewardToken1.getAddress(),
          distributionId1,
        );

      // Claim from second distribution
      await expect(rewardDistribution.connect(shareholder1).claimReward(distributionId2))
        .to.emit(rewardDistribution, 'RewardsClaimed')
        .withArgs(
          shareholder1.address,
          ethers.parseUnits('250', 18),
          await rewardToken2.getAddress(),
          distributionId2,
        );

      // Verify balances
      expect(await rewardToken1.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('250', 18),
      );
      expect(await rewardToken2.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('250', 18),
      );
    });

    it('should handle claimAllRewards with multiple distributions', async () => {
      await time.increase(201); // Fast forward past both distribution times

      // Claim all rewards at once
      await rewardDistribution.connect(shareholder1).claimAllRewards();

      // Verify balances for both tokens
      expect(await rewardToken1.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('250', 18),
      );
      expect(await rewardToken2.balanceOf(shareholder1.address)).to.equal(
        ethers.parseUnits('250', 18),
      );
    });
  });
});
