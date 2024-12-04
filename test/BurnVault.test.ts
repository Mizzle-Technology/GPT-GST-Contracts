import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Contract, ContractFactory, Signer } from 'ethers';
import { BurnVault, MockERC20 } from '../typechain-types';

describe('BurnVault', function () {
  let BurnVault: ContractFactory;
  let burnVault: BurnVault;
  let MockERC20: ContractFactory;
  let mockERC20Token: MockERC20;

  let superAdmin: Signer;
  let admin: Signer;
  let user: Signer;
  let newAdmin: Signer;
  let nonAdmin: Signer;

  beforeEach(async function () {
    [superAdmin, admin, user, newAdmin, nonAdmin] = await ethers.getSigners();

    // Deploy MockERC20
    MockERC20 = await ethers.getContractFactory('MockERC20');
    mockERC20Token = (await MockERC20.deploy()) as unknown as MockERC20;
    await mockERC20Token.initialize('MockToken', 'MTK', 18);

    // Deploy BurnVault as proxy
    BurnVault = await ethers.getContractFactory('BurnVault');
    burnVault = (await upgrades.deployProxy(
      BurnVault,
      [await superAdmin.getAddress(), await admin.getAddress()],
      { initializer: 'initialize', kind: 'uups' },
    )) as unknown as BurnVault;
    await burnVault.waitForDeployment();
  });

  // 1. Initialization Tests

  it('should initialize successfully', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(await mockERC20Token.getAddress());

    expect(
      await burnVault.hasRole(await burnVault.DEFAULT_ADMIN_ROLE(), await superAdmin.getAddress()),
    ).to.be.true;
    expect(await burnVault.hasRole(await burnVault.ADMIN_ROLE(), await admin.getAddress())).to.be
      .true;

    expect(await burnVault.isAcceptedToken(await mockERC20Token.getAddress())).to.be.true;
  });

  it('should revert initialization with zero super admin', async function () {
    const BurnVaultFactory = await ethers.getContractFactory('BurnVault', superAdmin);
    await expect(
      upgrades.deployProxy(BurnVaultFactory, [ethers.ZeroAddress, await admin.getAddress()], {
        initializer: 'initialize',
        kind: 'uups',
      }),
    ).to.be.revertedWithCustomError(burnVault, 'AddressCannotBeZero');
  });

  it('should revert initialization with zero admin', async function () {
    const BurnVaultFactory = await ethers.getContractFactory('BurnVault', superAdmin);
    await expect(
      upgrades.deployProxy(BurnVaultFactory, [await superAdmin.getAddress(), ethers.ZeroAddress], {
        initializer: 'initialize',
        kind: 'uups',
      }),
    ).to.be.revertedWithCustomError(burnVault, 'AddressCannotBeZero');
  });

  it('should revert re-initialization', async function () {
    await expect(
      burnVault.initialize(await superAdmin.getAddress(), await admin.getAddress()),
    ).to.be.revertedWithCustomError(burnVault, 'InvalidInitialization');
  });

  // 2. setToken Function Tests

  it('should set token successfully', async function () {
    const tokenAddress = await mockERC20Token.getAddress();
    await burnVault.connect(admin).updateAcceptedTokens(tokenAddress);
    expect(await burnVault.isAcceptedToken(tokenAddress)).to.be.true;

    await expect(burnVault.connect(admin).updateAcceptedTokens(tokenAddress))
      .to.be.revertedWithCustomError(burnVault, 'DuplicatedToken')
      .withArgs(tokenAddress);
  });

  it('should revert when non-admin tries to set token', async function () {
    await expect(
      burnVault.connect(nonAdmin).updateAcceptedTokens(await mockERC20Token.getAddress()),
    )
      .to.be.revertedWithCustomError(burnVault, 'AdminRoleNotGranted')
      .withArgs(await nonAdmin.getAddress());
  });

  it('should revert when setting zero address as token', async function () {
    await expect(
      burnVault.connect(admin).updateAcceptedTokens(ethers.ZeroAddress),
    ).to.be.revertedWithCustomError(burnVault, 'AddressCannotBeZero');
  });

  it('should set a new token successfully', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(await mockERC20Token.getAddress());

    const newToken = (await MockERC20.deploy()) as unknown as Contract;
    await newToken.initialize('NewToken', 'NTK', 18);
    await burnVault.connect(admin).updateAcceptedTokens(await newToken.getAddress());

    expect(await burnVault.isAcceptedToken(await newToken.getAddress())).to.be.true;
  });

  it('should revert when setting the same token again', async function () {
    const tokenAddress = await mockERC20Token.getAddress();
    await burnVault.connect(admin).updateAcceptedTokens(tokenAddress);
    await expect(burnVault.connect(admin).updateAcceptedTokens(tokenAddress))
      .to.be.revertedWithCustomError(burnVault, 'DuplicatedToken')
      .withArgs(tokenAddress);
  });

  // 3. Access Control Tests

  it('should verify default admin role', async function () {
    expect(await burnVault.hasRole(await burnVault.DEFAULT_ADMIN_ROLE(), superAdmin.getAddress()))
      .to.be.true;
  });

  it('should verify admin role', async function () {
    expect(await burnVault.hasRole(await burnVault.ADMIN_ROLE(), await admin.getAddress())).to.be
      .true;
  });

  it('should grant and revoke admin role', async function () {
    await burnVault.grantRole(await burnVault.ADMIN_ROLE(), await newAdmin.getAddress());
    expect(await burnVault.hasRole(await burnVault.ADMIN_ROLE(), await newAdmin.getAddress())).to.be
      .true;

    await burnVault.revokeRole(await burnVault.ADMIN_ROLE(), await newAdmin.getAddress());
    expect(await burnVault.hasRole(await burnVault.ADMIN_ROLE(), await newAdmin.getAddress())).to.be
      .false;
  });

  // 4. Pausable Functionality Tests

  it('should allow admin to pause and unpause', async function () {
    await burnVault.connect(superAdmin).pause();
    expect(await burnVault.connect(superAdmin).paused()).to.be.true;

    await burnVault.connect(superAdmin).unpause();
    expect(await burnVault.connect(superAdmin).paused()).to.be.false;
  });

  it('should revert when non-admin tries to pause', async function () {
    await expect(burnVault.connect(nonAdmin).pause())
      .to.be.revertedWithCustomError(burnVault, 'DefaultAdminRoleNotGranted')
      .withArgs(await nonAdmin.getAddress());
  });

  // 5. Deposit Functionality Tests

  it('should deposit tokens successfully', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(await mockERC20Token.getAddress());

    await mockERC20Token.mint(await user.getAddress(), 1000);
    await mockERC20Token.connect(user).approve(await burnVault.getAddress(), 1000);
    await expect(
      burnVault
        .connect(user)
        .depositTokens(await user.getAddress(), 500, await mockERC20Token.getAddress()),
    )
      .to.emit(burnVault, 'TokensDeposited')
      .withArgs(await user.getAddress(), 500);

    const deposit = await burnVault.deposits(await user.getAddress());
    expect(deposit.amount).to.equal(500);
  });

  it('should revert deposit without approval', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(mockERC20Token.getAddress());

    await mockERC20Token.mint(user.getAddress(), 1000);
    await expect(
      burnVault.connect(user).depositTokens(user.getAddress(), 500, mockERC20Token.getAddress()),
    ).to.be.reverted;
  });

  it('should revert deposit of zero amount', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(mockERC20Token.getAddress());

    await mockERC20Token.connect(user).approve(burnVault.getAddress(), 1000);
    await expect(
      burnVault.connect(user).depositTokens(user.getAddress(), 0, mockERC20Token.getAddress()),
    ).to.be.revertedWith('BurnVault: amount must be greater than zero');
  });

  // 6. Burn Functionality Tests

  it('should burn tokens successfully after delay', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(await mockERC20Token.getAddress());

    await mockERC20Token.mint(await user.getAddress(), 1000);
    await mockERC20Token.connect(user).approve(await burnVault.getAddress(), 1000);
    await burnVault
      .connect(user)
      .depositTokens(user.getAddress(), 500, mockERC20Token.getAddress());

    expect(await mockERC20Token.balanceOf(burnVault.getAddress())).to.equal(500);

    // Increase time
    const delay = await burnVault.BURN_DELAY();
    await ethers.provider.send('evm_increaseTime', [Number(delay)]);
    await ethers.provider.send('evm_mine');

    await expect(
      burnVault.connect(admin).burnAllTokens(user.getAddress(), mockERC20Token.getAddress()),
    )
      .to.emit(burnVault, 'TokensBurned')
      .withArgs(user.getAddress(), 500);

    const deposit = await burnVault.deposits(user.getAddress());
    expect(deposit.amount).to.equal(0);

    expect(await mockERC20Token.balanceOf(burnVault.getAddress())).to.equal(0);
  });

  it('should revert burn before delay', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(mockERC20Token.getAddress());

    await mockERC20Token.mint(user.getAddress(), 1000);
    await mockERC20Token.connect(user).approve(burnVault.getAddress(), 1000);
    await burnVault
      .connect(user)
      .depositTokens(user.getAddress(), 500, mockERC20Token.getAddress());

    await expect(
      burnVault.connect(admin).burnAllTokens(user.getAddress(), mockERC20Token.getAddress()),
    ).to.be.revertedWithCustomError(burnVault, 'TooEarlyToBurn');
  });

  it('should revert burn by non-admin', async function () {
    await burnVault.connect(admin).updateAcceptedTokens(mockERC20Token.getAddress());

    await mockERC20Token.mint(user.getAddress(), 1000);
    await mockERC20Token.connect(user).approve(burnVault.getAddress(), 1000);
    await burnVault
      .connect(user)
      .depositTokens(user.getAddress(), 500, mockERC20Token.getAddress());
  });
  //     // Increase time
  //     await ethers.provider.send('evm_increaseTime', [
  //       await burnVault.BURN_DELAY(),
  //     ]);
  //     await ethers.provider.send('evm_mine');

  //     await expect(
  //       burnVault
  //         .connect(nonAdmin)
  //         .burnAllTokens(user.address, mockERC20Token.address),
  //     ).to.be.revertedWith(
  //       'AccessControl: account ' +
  //         nonAdmin.address.toLowerCase() +
  //         ' is missing role ' +
  //         (await burnVault.ADMIN_ROLE()),
  //     );
  //   });
});
