// test/GoldPackgpt.test.js

import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { GoldPackToken, MockERC20 } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

describe('GoldPackToken', function () {
  let gpt: GoldPackToken;

  // Roles
  let superAdmin: SignerWithAddress;
  let admin: SignerWithAddress;
  let sales: SignerWithAddress;
  let user: SignerWithAddress;
  let alice: SignerWithAddress;
  let gptproxy: string;

  beforeEach(async function () {
    [superAdmin, admin, sales, user, alice] = await ethers.getSigners();

    // Deploy GoldPackToken using UUPS proxy
    const gpt_factory = await ethers.getContractFactory('GoldPackToken', superAdmin);

    gpt = (await upgrades.deployProxy(
      gpt_factory,
      [await superAdmin.getAddress(), await admin.getAddress(), await sales.getAddress()],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as GoldPackToken;
    await gpt.waitForDeployment();
    gptproxy = await gpt.getAddress();

    // Grant roles
    const SALES_ROLE = await gpt.SALES_ROLE();
    await gpt.grantRole(SALES_ROLE, sales.address);
  });

  it('Should set up correctly', async function () {
    // Verify roles
    const DEFAULT_ADMIN_ROLE = await gpt.DEFAULT_ADMIN_ROLE();
    const ADMIN_ROLE = await gpt.ADMIN_ROLE();
    const SALES_ROLE = await gpt.SALES_ROLE();

    expect(await gpt.hasRole(DEFAULT_ADMIN_ROLE, await superAdmin.getAddress())).to.be.true;
    expect(await gpt.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    expect(await gpt.hasRole(SALES_ROLE, sales.address)).to.be.true;

    // Verify token properties
    expect(await gpt.decimals()).to.equal(6);
  });

  it('Should pause and unpause correctly', async function () {
    // Pause the contract
    await expect(gpt.connect(admin).pause()).to.emit(gpt, 'Paused');
    expect(await gpt.paused()).to.be.true;

    // Unpause the contract
    await expect(gpt.connect(admin).unpause()).to.emit(gpt, 'Unpaused');
    expect(await gpt.paused()).to.be.false;
  });

  it('Should mint correctly', async function () {
    const amount = 10_000_000000;
    await gpt.connect(sales).mint(user.getAddress(), amount);
    expect(await gpt.balanceOf(user.getAddress())).to.equal(amount);
  });

  it('Should fail minting when paused', async function () {
    await gpt.connect(admin).pause();
    await expect(
      gpt.connect(sales).mint(user.getAddress(), 10_000_000000),
    ).to.be.revertedWithCustomError(gpt, 'EnforcedPause');
  });

  it('Should fail when a non-sales role tries to mint', async function () {
    await expect(gpt.connect(user).mint(user.getAddress(), 10_000_000000))
      .to.be.revertedWithCustomError(gpt, 'SalesRoleNotGranted')
      .withArgs(user.address);
  });

  describe('Core ERC20 Functionality', () => {
    it('should have correct name and symbol', async () => {
      expect(await gpt.name()).to.equal('GoldPack Token');
      expect(await gpt.symbol()).to.equal('GPT');
    });

    it('should have correct decimals', async () => {
      expect(await gpt.decimals()).to.equal(6);
    });
  });

  describe('Role Management', () => {
    it('should check role assignments correctly', async () => {
      expect(await gpt.isAdmin(admin.address)).to.be.true;
      expect(await gpt.isSales(sales.address)).to.be.true;
      expect(await gpt.isAdmin(user.address)).to.be.false;
      expect(await gpt.isSales(user.address)).to.be.false;
    });

    it('should emit events when roles are granted', async () => {
      const newSales = await ethers.provider.getSigner(10);
      await expect(gpt.connect(superAdmin).grantRole(await gpt.SALES_ROLE(), newSales.address))
        .to.emit(gpt, 'RoleGranted')
        .withArgs(await gpt.SALES_ROLE(), newSales.address, superAdmin.address);
    });

    it('should allow DEFAULT_ADMIN to grant sales role', async () => {
      await expect(gpt.connect(superAdmin).grantSalesRole(alice.address))
        .to.emit(gpt, 'SalesRoleGranted')
        .withArgs(alice.address);
      expect(await gpt.isSales(alice.address)).to.be.true;
    });

    it('should allow DEFAULT_ADMIN to grant admin role', async () => {
      await expect(gpt.connect(superAdmin).grantAdminRole(alice.address))
        .to.emit(gpt, 'AdminRoleGranted')
        .withArgs(alice.address);
      expect(await gpt.isAdmin(alice.address)).to.be.true;
    });
  });

  describe('UUPS Upgradeability', () => {
    it('should only allow DEFAULT_ADMIN_ROLE to upgrade', async () => {
      const GoldPackTokenV2 = await ethers.getContractFactory('GoldPackToken');
      await expect(upgrades.upgradeProxy(await gpt.getAddress(), GoldPackTokenV2.connect(user)))
        .to.be.revertedWithCustomError(gpt, 'DefaultAdminRoleNotGranted')
        .withArgs(user.address);
    });
  });

  describe('Role Management and Emergency Functions', () => {
    describe('revokeSalesRole', () => {
      it('should allow DEFAULT_ADMIN to revoke sales role', async () => {
        const SALES_ROLE = await gpt.SALES_ROLE();
        await gpt.grantRole(SALES_ROLE, alice.address);
        expect(await gpt.isSales(alice.address)).to.be.true;

        await gpt.revokeSalesRole(alice.address);
        expect(await gpt.isSales(alice.address)).to.be.false;
      });

      it('should revert if caller is not DEFAULT_ADMIN', async () => {
        await expect(gpt.connect(user).revokeSalesRole(sales.address))
          .to.be.revertedWithCustomError(gpt, 'DefaultAdminRoleNotGranted')
          .withArgs(user.address);
      });
    });

    describe('revokeAdminRole', () => {
      it('should allow DEFAULT_ADMIN to revoke admin role', async () => {
        const ADMIN_ROLE = await gpt.ADMIN_ROLE();
        await gpt.grantRole(ADMIN_ROLE, alice.address);
        expect(await gpt.isAdmin(alice.address)).to.be.true;

        await gpt.revokeAdminRole(alice.address);
        expect(await gpt.isAdmin(alice.address)).to.be.false;
      });

      it('should revert if caller is not DEFAULT_ADMIN', async () => {
        await expect(gpt.connect(user).revokeAdminRole(admin.address))
          .to.be.revertedWithCustomError(gpt, 'DefaultAdminRoleNotGranted')
          .withArgs(user.address);
      });
    });

    describe('emergencyWithdraw', () => {
      let mockToken: MockERC20;

      beforeEach(async () => {
        // Deploy a mock ERC20 token for testing emergency withdrawals
        const MockERC20 = await ethers.getContractFactory('MockERC20');
        mockToken = (await MockERC20.deploy()) as unknown as MockERC20;
        await mockToken.initialize('Mock Token', 'MTK', 18);
        await mockToken.mint(gptproxy, ethers.parseEther('1000'));
      });

      it('should allow DEFAULT_ADMIN to withdraw tokens when paused', async () => {
        await gpt.connect(admin).pause();
        const amount = ethers.parseEther('100');

        const balanceBefore = await mockToken.balanceOf(alice.address);
        await gpt
          .connect(superAdmin)
          .emergencyWithdraw(await mockToken.getAddress(), alice.address, amount);
        const balanceAfter = await mockToken.balanceOf(alice.address);

        expect(balanceAfter - balanceBefore).to.equal(amount);
      });

      it('should revert if contract is not paused', async () => {
        await expect(
          gpt.emergencyWithdraw(await mockToken.getAddress(), user.address, 100),
        ).to.be.revertedWithCustomError(gpt, 'ExpectedPause');
      });

      it('should revert if trying to withdraw GPT tokens', async () => {
        await gpt.connect(admin).pause();
        await expect(
          gpt.connect(superAdmin).emergencyWithdraw(gptproxy, alice.address, 100),
        ).to.be.revertedWithCustomError(gpt, 'CannotWithdrawGptTokens');
      });

      it('should revert if caller is not DEFAULT_ADMIN', async () => {
        await gpt.connect(admin).pause();
        await expect(
          gpt.connect(user).emergencyWithdraw(await mockToken.getAddress(), alice.address, 100),
        )
          .to.be.revertedWithCustomError(gpt, 'DefaultAdminRoleNotGranted')
          .withArgs(user.address);
      });
    });
  });
});
