// test/GoldPackgpt.test.js

import { expect } from 'chai';
import { ethers, upgrades, network } from 'hardhat';
import { GoldPackToken, BurnVault } from '../typechain-types';

describe('GoldPackToken', function () {
  let gpt: GoldPackToken;
  let burnVault: BurnVault;

  // Roles
  let superAdmin: any;
  let admin: any;
  let sales: any;
  let user: any;
  let burnVaultProxy: string;
  let gptproxy: string;
  let addrs;

  const ONE_DAY_IN_SECONDS = 86400;

  // Helper function to increase time
  async function increaseTime(seconds: number | bigint) {
    await ethers.provider.send('evm_increaseTime', [seconds]);
    await ethers.provider.send('evm_mine', []);
  }

  beforeEach(async function () {
    [superAdmin, admin, sales, user, ...addrs] = await ethers.getSigners();

    // Step 1: Deploy BurnVault using UUPS proxy
    const BurnVault_factory = await ethers.getContractFactory(
      'BurnVault',
      superAdmin,
    );
    burnVault = (await upgrades.deployProxy(
      BurnVault_factory,
      [superAdmin.address, admin.address],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as BurnVault;
    await burnVault.waitForDeployment();
    burnVaultProxy = await burnVault.getAddress();
    // console.log("BurnVault deployed to:", burnVaultProxy);

    // Step 2: Deploy GoldPackToken using UUPS proxy
    const gpt_factory = await ethers.getContractFactory(
      'GoldPackToken',
      superAdmin,
    );

    gpt = (await upgrades.deployProxy(
      gpt_factory,
      [superAdmin.address, admin.address, sales.address],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as GoldPackToken;
    await gpt.waitForDeployment();
    gptproxy = await gpt.getAddress();
    // console.log("GoldPackToken deployed to:", gptproxy);

    // Step 3: Set token in vault
    await burnVault.connect(admin).updateAcceptedTokens(gptproxy);

    // Set burn vault address in token
    await gpt.connect(superAdmin).setBurnVault(burnVaultProxy);

    // Step 4: Grant roles
    const SALES_ROLE = await gpt.SALES_ROLE();
    await gpt.grantRole(SALES_ROLE, sales.address);

    // Step 5: Grant Admin role to token contract in vault
    const ADMIN_ROLE = await burnVault.ADMIN_ROLE();
    await burnVault.grantRole(ADMIN_ROLE, gptproxy);
  });

  it('Should set up correctly', async function () {
    // Verify that the BurnVault has the correct token address
    expect(await burnVault.isAcceptedToken(gptproxy)).to.be.true;

    // Verify roles
    const DEFAULT_ADMIN_ROLE = await gpt.DEFAULT_ADMIN_ROLE();
    const ADMIN_ROLE = await gpt.ADMIN_ROLE();
    const SALES_ROLE = await gpt.SALES_ROLE();

    expect(await gpt.hasRole(DEFAULT_ADMIN_ROLE, superAdmin.address)).to.be
      .true;
    expect(await gpt.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    expect(await gpt.hasRole(SALES_ROLE, sales.address)).to.be.true;

    // Verify token properties
    expect(await gpt.decimals()).to.equal(6);
    expect(await gpt.getBurnVaultAddress()).to.equal(burnVaultProxy);
  });

  it('Should pause and unpause correctly', async function () {
    // Pause the contract
    expect(await gpt.connect(admin).pause()).to.emit(gpt, 'Paused');

    expect(await gpt.paused()).to.be.true;

    // Unpause the contract
    expect(await gpt.connect(admin).unpause()).to.emit(gpt, 'Unpaused');

    expect(await gpt.paused()).to.be.false;
  });

  it('Should mint correctly', async function () {
    const amount = 10_000_000000;

    await gpt.connect(sales).mint(user.address, amount);

    expect(await gpt.balanceOf(user.address)).to.equal(amount);
  });

  it('Should perform vault operations correctly', async function () {
    const amount = await gpt.TOKENS_PER_TROY_OUNCE();

    // Mint tokens to user
    await gpt.connect(sales).mint(user.address, amount);

    // Deposit to vault
    await gpt.connect(user).approve(burnVaultProxy, amount);
    await gpt.connect(user).depositToBurnVault(amount);

    expect(await burnVault.getBalance(user.address)).to.equal(amount);

    // Wait burn delay
    const burnDelay = await burnVault.BURN_DELAY();
    const burnDelayNumber = Number(burnDelay);
    if (!Number.isSafeInteger(burnDelayNumber)) {
      throw new Error('burnDelay exceeds Number.MAX_SAFE_INTEGER');
    }
    // Move forward in time
    await ethers.provider.send('evm_increaseTime', [burnDelayNumber]);
    await ethers.provider.send('evm_mine', []);

    // Burn tokens
    await gpt.connect(sales).RedeemCoins(user.address, amount);

    expect(await burnVault.getBalance(user.address)).to.equal(0);
  });

  it('Should fail minting when paused', async function () {
    // Pause the contract
    await gpt.connect(admin).pause();

    // Attempt to mint
    await expect(
      gpt.connect(sales).mint(user.address, await gpt.TOKENS_PER_TROY_OUNCE()),
    ).to.be.revertedWithCustomError(gpt, 'EnforcedPause');
  });

  it('Should fail when a non-sales role tries to mint', async function () {
    // Attempt to mint
    const SALES_ROLE = await gpt.SALES_ROLE();

    await expect(
      gpt.connect(user).mint(user.address, await gpt.TOKENS_PER_TROY_OUNCE()),
    )
      .to.be.revertedWithCustomError(gpt, 'SalesRoleNotGranted')
      .withArgs(user.address);
  });

  it('Should fail when depositing invalid amount to vault', async function () {
    const TOZ = await gpt.TOKENS_PER_TROY_OUNCE();
    const invalidAmount = TOZ + 1n;

    await expect(
      gpt.connect(user).depositToBurnVault(invalidAmount),
    ).to.be.revertedWith(
      'GoldPackToken: amount must be a whole number of Troy ounces',
    );
  });

  it('Should not burn tokens before the burn delay has passed', async function () {
    const amount = await gpt.TOKENS_PER_TROY_OUNCE();

    // Mint tokens to the user
    await gpt.connect(sales).mint(user.address, amount);

    // Retrieve burn delay from BurnVault contract
    const burnDelay = await burnVault.BURN_DELAY();

    // Advance time by (burnDelay - 1) seconds to stay just before the burn delay
    await increaseTime(Number(burnDelay - 1n));

    // Approve the BurnVault to spend tokens on behalf of the user
    await gpt.connect(user).approve(burnVaultProxy, amount);

    const allowance = await gpt.allowance(user.address, burnVaultProxy);
    expect(allowance).to.equal(amount);

    // Deposit tokens to the BurnVault
    await gpt.connect(user).depositToBurnVault(amount);

    // Attempt to burn tokens before the delay period has passed
    await expect(
      gpt.connect(sales).RedeemAllCoins(user.address),
    ).to.be.revertedWithCustomError(burnVault, 'TooEarlyToBurn');
  });

  it('Should fail when unauthorized user tries to burn from vault', async function () {
    await expect(gpt.connect(user).RedeemAllCoins(user.address))
      .to.be.revertedWithCustomError(gpt, 'SalesRoleNotGranted')
      .withArgs(user.address);
  });
});
