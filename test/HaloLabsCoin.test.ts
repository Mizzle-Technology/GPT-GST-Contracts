import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { HaloLabsCoin } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { time } from '@nomicfoundation/hardhat-network-helpers';

describe('HaloLabsCoin', () => {
  let haloLabsCoin: HaloLabsCoin;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let recipient: SignerWithAddress;
  const INITIAL_SUPPLY = ethers.parseUnits('1000000000', 18); // 1 billion tokens

  beforeEach(async () => {
    [owner, admin, user, recipient] = await ethers.getSigners();

    const HaloLabsCoinFactory = await ethers.getContractFactory('HaloLabsCoin', owner);
    haloLabsCoin = (await upgrades.deployProxy(
      HaloLabsCoinFactory,
      [owner.address, admin.address],
      { initializer: 'initialize' },
    )) as unknown as HaloLabsCoin;
    await haloLabsCoin.waitForDeployment();
  });

  describe('Initialization', () => {
    it('should initialize with correct values', async () => {
      expect(await haloLabsCoin.name()).to.equal('Halo Labs Coin');
      expect(await haloLabsCoin.symbol()).to.equal('HLC');
      expect(await haloLabsCoin.decimals()).to.equal(18);
      expect(await haloLabsCoin.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await haloLabsCoin.balanceOf(await haloLabsCoin.getAddress())).to.equal(
        INITIAL_SUPPLY,
      );
    });

    it('should set correct roles', async () => {
      const ADMIN_ROLE = await haloLabsCoin.ADMIN_ROLE();
      const DEFAULT_ADMIN_ROLE = await haloLabsCoin.DEFAULT_ADMIN_ROLE();

      expect(await haloLabsCoin.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
      expect(await haloLabsCoin.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    });
  });

  describe('Distribution', () => {
    it('should distribute tokens when called by admin', async () => {
      const amount = ethers.parseUnits('1000', 18);
      const deadline = (await time.latest()) + 3600; // 1 hour from now

      // Generate permit signature
      const nonce = await haloLabsCoin.nonces(admin.address);
      const domain = {
        name: 'Halo Labs Coin',
        version: '1',
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await haloLabsCoin.getAddress(),
      };

      const types = {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      };

      const value = {
        owner: admin.address,
        spender: await haloLabsCoin.getAddress(),
        value: amount,
        nonce: nonce,
        deadline: deadline,
      };

      const signature = await admin.signTypedData(domain, types, value);
      const { v, r, s } = ethers.Signature.from(signature);

      await expect(
        haloLabsCoin.connect(admin).distribute(recipient.address, amount, deadline, v, r, s),
      )
        .to.emit(haloLabsCoin, 'TokensDistributed')
        .withArgs(recipient.address, amount);

      expect(await haloLabsCoin.balanceOf(recipient.address)).to.equal(amount);
    });

    it('should revert when called by non-admin', async () => {
      const amount = ethers.parseUnits('1000', 18);
      const deadline = (await time.latest()) + 3600;

      await expect(
        haloLabsCoin
          .connect(user)
          .distribute(recipient.address, amount, deadline, 0, ethers.ZeroHash, ethers.ZeroHash),
      )
        .to.be.revertedWithCustomError(haloLabsCoin, 'AdminRoleNotGranted')
        .withArgs(user.address);
    });

    it('should revert when recipient is zero address', async () => {
      const amount = ethers.parseUnits('1000', 18);
      const deadline = (await time.latest()) + 3600;

      await expect(
        haloLabsCoin
          .connect(admin)
          .distribute(ethers.ZeroAddress, amount, deadline, 0, ethers.ZeroHash, ethers.ZeroHash),
      ).to.be.revertedWithCustomError(haloLabsCoin, 'AddressCannotBeZero');
    });
  });

  describe('Pause/Unpause', () => {
    it('should allow admin to pause and unpause', async () => {
      await expect(haloLabsCoin.connect(admin).pause()).to.emit(haloLabsCoin, 'Paused');

      expect(await haloLabsCoin.paused()).to.be.true;

      await expect(haloLabsCoin.connect(admin).unpause()).to.emit(haloLabsCoin, 'Unpaused');

      expect(await haloLabsCoin.paused()).to.be.false;
    });

    it('should revert when non-admin tries to pause', async () => {
      await expect(haloLabsCoin.connect(user).pause()).to.be.revertedWithCustomError(
        haloLabsCoin,
        'AdminRoleNotGranted',
      );
    });
  });

  describe('Token Operations', () => {
    it('should not allow transfers when paused', async () => {
      const amount = ethers.parseUnits('1000', 18);

      // First distribute some tokens
      const deadline = (await time.latest()) + 3600;
      const nonce = await haloLabsCoin.nonces(admin.address);
      const signature = await admin.signTypedData(
        {
          name: 'Halo Labs Coin',
          version: '1',
          chainId: (await ethers.provider.getNetwork()).chainId,
          verifyingContract: await haloLabsCoin.getAddress(),
        },
        {
          Permit: [
            { name: 'owner', type: 'address' },
            { name: 'spender', type: 'address' },
            { name: 'value', type: 'uint256' },
            { name: 'nonce', type: 'uint256' },
            { name: 'deadline', type: 'uint256' },
          ],
        },
        {
          owner: admin.address,
          spender: await haloLabsCoin.getAddress(),
          value: amount,
          nonce: nonce,
          deadline: deadline,
        },
      );
      const { v, r, s } = ethers.Signature.from(signature);

      await haloLabsCoin.connect(admin).distribute(user.address, amount, deadline, v, r, s);

      // Pause the contract
      await haloLabsCoin.connect(admin).pause();

      // Try to transfer
      await expect(
        haloLabsCoin.connect(user).transfer(recipient.address, amount),
      ).to.be.revertedWithCustomError(haloLabsCoin, 'EnforcedPause');
    });
  });
});
