// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import 'forge-std/Test.sol';
import {BurnVault} from '../src/vault/BurnVault.sol';
import {MockERC20, MaliciousContract, ReentrantERC20} from './Mocks.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {Upgrades} from 'openzeppelin-foundry-upgrades/Upgrades.sol';

contract TestBurnVault is Test {
  event TokensDeposited(address indexed from, uint256 amount, uint256 timestamp);
  event TokensBurned(address indexed account, uint256 amount);

  BurnVault vault;
  MockERC20 token;
  address superAdmin = address(0x1);
  address admin = address(0x2);
  address user = address(0x3);
  address newAdmin = address(0x4);
  address nonAdmin = address(0x5);
  address proxy;

  function setUp() public {
    // Deploy MockERC20
    token = new MockERC20();
    token.initialize('MockToken', 'MTK', 18);
    // Deploy BurnVault
    vm.startPrank(superAdmin);
    vault = new BurnVault();
    vm.stopPrank();
  }

  // 1. Initialization Tests

  function test_initialize_success() public {
    vm.startPrank(superAdmin);
    // deploy the proxy
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault instance = BurnVault(proxy);
    instance.updateAcceptedTokens(token);
    vm.stopPrank();

    // Verify roles
    assertTrue(instance.hasRole(instance.DEFAULT_ADMIN_ROLE(), superAdmin));
    assertTrue(instance.hasRole(instance.ADMIN_ROLE(), admin));

    // Verify _initialized is false
    // Note: _initialized is private, so we rely on behavior or events
    // Alternatively, expose a getter in BurnVault for testing purposes
  }

  function test_initialize_zero_super_revert() public {
    vm.startPrank(superAdmin);
    vm.expectRevert(bytes('BurnVault: the default admin cannot be the zero address'));
    vault.initialize(address(0), admin);
    vm.stopPrank();
  }

  function test_initialize_zero_admin_revert() public {
    vm.startPrank(superAdmin);
    vm.expectRevert(bytes('BurnVault: the admin cannot be the zero address'));
    vault.initialize(superAdmin, address(0));
    vm.stopPrank();
  }

  function test_initialize_reinitialization_revert() public {
    // First initialization
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);

    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    vault.updateAcceptedTokens(_token);
    vm.stopPrank();

    // Attempt re-initialization
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize(superAdmin, admin);
  }

  // 2. setToken Function Tests

  function test_setToken_success() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();

    // Verify token is set
    assertTrue(BurnVault(proxy).isAcceptedToken(address(token)));

    // Verify _initialized is true by attempting to setToken again
    vm.startPrank(superAdmin);
    vm.expectRevert(bytes('BurnVault: token already added'));
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();
  }

  function test_setToken_nonAdmin_revert() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();

    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSignature(
        'AccessControlUnauthorizedAccount(address,bytes32)',
        nonAdmin,
        vault.DEFAULT_ADMIN_ROLE()
      )
    );
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();
  }

  function test_setToken_zero_address_revert() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vm.expectRevert(bytes('BurnVault: token cannot be the zero address'));
    BurnVault(proxy).updateAcceptedTokens(ERC20BurnableUpgradeable(address(0)));
    vm.stopPrank();
  }

  function test_setToken_newtoken() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);

    MockERC20 newToken = new MockERC20();
    newToken.initialize('NewToken', 'NTK', 18);
    BurnVault(proxy).updateAcceptedTokens(newToken);
    vm.stopPrank();

    assertTrue(BurnVault(proxy).isAcceptedToken(address(newToken)));
  }

  function test_setToken_sametoken() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);

    vm.expectRevert(bytes('BurnVault: token already added'));
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();
  }

  // 3. Access Control Tests

  function test_verify_default_admin_role() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);
    vault.updateAcceptedTokens(token);
    vm.stopPrank();
    assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), superAdmin));
  }

  function test_verify_admin_role() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);
    vault.updateAcceptedTokens(token);
    vm.stopPrank();

    assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));
  }

  function test_grant_revoke_admin_role() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);
    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    vault.updateAcceptedTokens(_token);
    vm.stopPrank();

    vm.startPrank(superAdmin);
    vault.grantRole(vault.ADMIN_ROLE(), newAdmin);
    assertTrue(vault.hasRole(vault.ADMIN_ROLE(), newAdmin));

    vault.revokeRole(vault.ADMIN_ROLE(), newAdmin);
    assertFalse(vault.hasRole(vault.ADMIN_ROLE(), newAdmin));
    vm.stopPrank();
  }

  // 4. Pausable Functionality Tests

  function test_pause_unpause_by_admin() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);
    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    vault.updateAcceptedTokens(_token);

    vault.pause();
    // Assuming BurnVault has a paused() function
    assertTrue(vault.paused());

    vault.unpause();
    assertFalse(vault.paused());
    vm.stopPrank();
  }

  function test_pause_by_non_admin_revert() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);

    vm.stopPrank();

    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSignature(
        'AccessControlUnauthorizedAccount(address,bytes32)',
        nonAdmin,
        vault.DEFAULT_ADMIN_ROLE()
      )
    );
    vault.pause();
    vm.stopPrank();
  }

  // 5. Deposit Functionality Tests

  function test_deposit_success() public {
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);
    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    vault.updateAcceptedTokens(_token);
    vm.stopPrank();

    // Mint tokens to user
    token.mint(user, 1000);

    // Approve vault
    vm.startPrank(user);
    token.approve(address(vault), 1000);

    // Expect event
    vm.expectEmit(true, true, false, true);
    emit TokensDeposited(user, 500, block.timestamp);

    // Deposit tokens
    vault.depositTokens(user, 500, _token);
    vm.stopPrank();

    // Verify deposit
    (uint256 amount, ) = vault.deposits(user);
    assertEq(amount, 500);
  }

  function test_deposit_without_approval_revert() public {
    // Set token
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();

    // Mint tokens to user
    token.mint(user, 1000);

    // Do not approve
    vm.startPrank(user);

    vm.expectRevert();
    vault.depositTokens(user, 500, token);
    vm.stopPrank();
  }

  function test_deposit_zero_revert() public {
    // Set token
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault(proxy).updateAcceptedTokens(token);
    vm.stopPrank();

    // Approve vault
    vm.startPrank(user);
    token.approve(address(vault), 1000);

    // Attempt to deposit zero
    vm.expectRevert(bytes('BurnVault: amount must be greater than zero'));
    vault.depositTokens(user, 0, token);
    vm.stopPrank();
  }

  // 6. Burn Functionality Tests

  function test_burn_success_after_delay() public {
    // Set token
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    vault = BurnVault(proxy);

    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    vault.updateAcceptedTokens(_token);
    vm.stopPrank();

    // Mint and deposit tokens
    token.mint(user, 1000);
    vm.startPrank(user);
    token.approve(address(vault), 1000);
    vault.depositTokens(user, 500, _token);
    vm.stopPrank();

    // Verify vault's balance after deposit
    uint256 vaultBalance = token.balanceOf(address(vault));
    assertEq(vaultBalance, 500, 'Vault balance should be 500 after deposit');

    // Advance time
    vm.warp(block.timestamp + vault.BURN_DELAY() + 1);

    // Expect event
    vm.expectEmit(true, true, false, true);
    emit TokensBurned(user, 500);

    // Burn tokens
    vm.startPrank(admin);
    vault.burnAllTokens(user, _token);
    vm.stopPrank();

    // Verify deposit is deleted
    (uint256 amount, ) = vault.deposits(user);
    assertEq(amount, 0, 'Deposit amount should be zero after burn');

    // Verify vault's balance after burn
    vaultBalance = token.balanceOf(address(vault));
    assertEq(vaultBalance, 0, 'Vault balance should be zero after burn');
  }

  function test_burn_before_delay_revert() public {
    // Set token
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault proxyInstance = BurnVault(proxy);
    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    proxyInstance.updateAcceptedTokens(_token);
    vm.stopPrank();

    // Mint and deposit tokens
    token.mint(user, 1000);
    vm.startPrank(user);
    token.approve(address(proxyInstance), 1000);
    proxyInstance.depositTokens(user, 500, _token);
    vm.stopPrank();

    // Attempt to burn before delay
    vm.startPrank(admin);
    vm.expectRevert(bytes('BurnVault: burn delay not reached'));
    proxyInstance.burnTokens(user, 500, _token);
    vm.stopPrank();
  }

  function test_burn_by_non_admin_revert() public {
    // Set token
    vm.startPrank(superAdmin);
    proxy = Upgrades.deployUUPSProxy(
      'BurnVault.sol',
      abi.encodeCall(BurnVault.initialize, (superAdmin, admin))
    );
    BurnVault proxyInstance = BurnVault(proxy);
    ERC20BurnableUpgradeable _token = ERC20BurnableUpgradeable(address(token));
    proxyInstance.updateAcceptedTokens(_token);
    vm.stopPrank();

    // Mint and deposit tokens
    token.mint(user, 1000);
    vm.startPrank(user);
    token.approve(address(proxyInstance), 1000);
    proxyInstance.depositTokens(user, 500, _token);
    vm.stopPrank();

    // Advance time
    vm.warp(block.timestamp + vault.BURN_DELAY() + 1);

    // Attempt to burn by non-admin
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSignature(
        'AccessControlUnauthorizedAccount(address,bytes32)',
        nonAdmin,
        proxyInstance.ADMIN_ROLE()
      )
    );
    proxyInstance.burnAllTokens(user, _token);
    vm.stopPrank();
  }
}
