// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {Upgrades} from 'openzeppelin-foundry-upgrades/Upgrades.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import '../src/rewards/RewardDistribution.sol';
import '../src/rewards/IRewardDistribution.sol';
import './Mocks.sol'; // Mock contracts

contract RewardDistributionTest is Test {
  // Mocked Contracts

  MockERC20 private rewardToken1;
  MockERC20 private rewardToken2;
  RewardDistribution private rewardDistribution;

  // Roles
  bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00; // OpenZeppelin default
  bytes32 private constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  // Addresses
  address private superAdmin = address(5);
  address private admin = address(1);
  address private nonAdmin = address(6);
  address private shareholder1 = address(2);
  address private shareholder2 = address(3);
  address private anotherAdmin = address(4);
  address private newSuperAdmin = address(7);

  // Contract Proxy
  address private rewardDistributionProxy;

  // Events
  event SharesAllocated(address indexed account, uint256 shares);
  event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
  event ShareholderRemoved(address indexed account);
  event RewardTokenAdded(address indexed token);
  event RewardTokenRemoved(address indexed token);
  event RewardToppedUp(uint256 amount);
  event RewardsClaimed(
    address indexed shareholder,
    uint256 amount,
    address indexed token,
    bytes32 distributionId
  );
  event RewardsLocked(address indexed user);
  event RewardsUnlocked(address indexed user);
  event RewardsDistributed(bytes32 indexed distributionId, uint256 totalRewards);
  event Paused(address account);
  event Unpaused(address account);

  // Custom Errors
  error AccessControlUnauthorizedAccount(address account, bytes32 role);

  function setUp() public {
    // Deploy Mock ERC20 Tokens
    rewardToken1 = new MockERC20();
    rewardToken1.initialize('Reward Token 1', 'RT1', 18);

    rewardToken2 = new MockERC20();
    rewardToken2.initialize('Reward Token 2', 'RT2', 18);

    // Deploy RewardDistribution Proxy
    vm.startPrank(superAdmin);
    rewardDistribution = new RewardDistribution();
    rewardDistributionProxy = Upgrades.deployUUPSProxy(
      'RewardDistribution.sol:RewardDistribution',
      abi.encodeCall(RewardDistribution.initialize, (superAdmin, admin))
    );
    rewardDistribution = RewardDistribution(rewardDistributionProxy);
    vm.stopPrank();
  }

  // === 1. Initialization Tests ===

  function test_initialize_success() public view {
    // Verify roles
    assertTrue(rewardDistribution.hasRole(DEFAULT_ADMIN_ROLE, superAdmin));
    assertTrue(rewardDistribution.hasRole(ADMIN_ROLE, admin));

    // Verify initial state
    assertEq(rewardDistribution.totalShares(), 1e18, 'Total shares should be initialized to SCALE');
  }

  function test_initialize_zero_super_admin_revert() public {
    // Deploy a new proxy with zero superAdmin
    vm.startPrank(superAdmin);
    vm.expectRevert(bytes('BurnVault: the default admin cannot be the zero address'));
    Upgrades.deployUUPSProxy(
      'src/rewards/RewardDistribution.sol:RewardDistribution',
      abi.encodeCall(RewardDistribution.initialize, (address(0), admin))
    );
    vm.stopPrank();
  }

  function test_initialize_zero_admin_revert() public {
    vm.startPrank(superAdmin);
    vm.expectRevert(bytes('BurnVault: the admin cannot be the zero address'));
    Upgrades.deployUUPSProxy(
      'src/rewards/RewardDistribution.sol:RewardDistribution',
      abi.encodeCall(RewardDistribution.initialize, (superAdmin, address(0)))
    );
    vm.stopPrank();
  }

  function test_reinitialize_revert() public {
    vm.startPrank(superAdmin);
    vm.expectRevert('Initializable: contract is already initialized');
    rewardDistribution.initialize(superAdmin, admin);
    vm.stopPrank();
  }

  // === 2. Allocate Shares Tests ===

  function test_allocateShares_success() public {
    vm.startPrank(admin);
    rewardDistribution.allocateShares(shareholder1, 500e18);
    vm.stopPrank();

    (uint256 shares, , ) = rewardDistribution.getShareholders(shareholder1);
    assertEq(shares, 500e18, 'Shareholder shares should be 500e18');
    assertTrue(rewardDistribution.hasRole(ADMIN_ROLE, admin)); // Ensure admin role is intact
  }

  function test_allocateShares_exceed_scale_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Total shares exceed maximum'));
    rewardDistribution.allocateShares(shareholder1, 2e18); // Exceeds SCALE of 1e18
    vm.stopPrank();
  }

  function test_allocateShares_zero_address_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Invalid account address'));
    rewardDistribution.allocateShares(address(0), 100e18);
    vm.stopPrank();
  }

  function test_allocateShares_when_paused_revert() public {
    vm.startPrank(superAdmin);
    rewardDistribution.pause();
    vm.stopPrank();

    vm.startPrank(admin);
    vm.expectRevert('Pausable: paused');
    rewardDistribution.allocateShares(shareholder1, 100e18);
    vm.stopPrank();
  }

  // === 3. Update Shareholder Shares Tests ===

  function test_updateShareholderShares_success() public {
    // Allocate initial shares
    vm.startPrank(admin);
    rewardDistribution.allocateShares(shareholder1, 500e18);
    rewardDistribution.updateShareholderShares(shareholder1, 800e18);
    vm.stopPrank();

    (uint256 shares, , ) = rewardDistribution.getShareholders(shareholder1);
    assertEq(shares, 800e18, 'Shareholder shares should be updated to 800e18');
  }

  function test_updateShareholderShares_exceed_scale_revert() public {
    // Allocate initial shares
    vm.startPrank(admin);
    rewardDistribution.allocateShares(shareholder1, 900e18);
    vm.expectRevert(bytes('RewardDistribution: total shares exceed maximum'));
    rewardDistribution.updateShareholderShares(shareholder1, 200e18); // Total would be 1.1e18
    vm.stopPrank();
  }

  function test_updateShareholderShares_remove_shareholder() public {
    // Allocate initial shares
    vm.startPrank(admin);
    rewardDistribution.allocateShares(shareholder1, 500e18);
    // Update shares to zero to remove
    rewardDistribution.updateShareholderShares(shareholder1, 0);
    vm.stopPrank();

    (uint256 shares, , ) = rewardDistribution.getShareholders(shareholder1);
    assertEq(shares, 0, 'Shareholder shares should be zero');
    assertFalse(
      rewardDistribution.hasRole(ADMIN_ROLE, shareholder1),
      'Shareholder should no longer have ADMIN_ROLE'
    );
  }

  function test_updateShareholderShares_zero_address_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('RewardDistribution: invalid account address'));
    rewardDistribution.updateShareholderShares(address(0), 100e18);
    vm.stopPrank();
  }

  // === 4. Add/Remove Reward Token Tests ===

  function test_addRewardToken_success() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.stopPrank();

    assertTrue(
      rewardDistribution.supportTokens(address(rewardToken1)),
      'Token should be supported'
    );
    assertTrue(
      rewardDistribution.isRewardToken(address(rewardToken1)),
      'Token should be in rewardTokens set'
    );
  }

  function test_addRewardToken_already_supported_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.expectRevert(bytes('Token already supported'));
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.stopPrank();
  }

  function test_addRewardToken_zero_address_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Invalid token address'));
    rewardDistribution.addRewardToken(address(0));
    vm.stopPrank();
  }

  function test_addRewardToken_non_admin_revert() public {
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.stopPrank();
  }

  function test_removeRewardToken_success() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardDistribution.removeRewardToken(address(rewardToken1));
    vm.stopPrank();

    assertFalse(
      rewardDistribution.supportTokens(address(rewardToken1)),
      'Token should not be supported'
    );
    assertFalse(
      rewardDistribution.isRewardToken(address(rewardToken1)),
      'Token should not be in rewardTokens set'
    );
  }

  function test_removeRewardToken_not_supported_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Token not supported'));
    rewardDistribution.removeRewardToken(address(rewardToken1));
    vm.stopPrank();
  }

  function test_removeRewardToken_zero_address_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Invalid token address'));
    rewardDistribution.removeRewardToken(address(0));
    vm.stopPrank();
  }

  function test_removeRewardToken_non_admin_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.stopPrank();

    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.removeRewardToken(address(rewardToken1));
    vm.stopPrank();
  }

  // === 5. Top Up Rewards Tests ===

  function test_topUpRewards_success() public {
    // Add reward token
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    // Mint and approve tokens to admin
    rewardToken1.mint(admin, 1000e18);
    rewardToken1.approve(address(rewardDistribution), 1000e18);
    // Top up rewards
    rewardDistribution.topUpRewards(500e18, address(rewardToken1));
    vm.stopPrank();

    assertEq(
      rewardToken1.balanceOf(address(rewardDistribution)),
      500e18,
      'RewardDistribution should have 500e18 tokens'
    );
  }

  function test_topUpRewards_zero_amount_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.expectRevert(bytes('Amount must be greater than zero'));
    rewardDistribution.topUpRewards(0, address(rewardToken1));
    vm.stopPrank();
  }

  function test_topUpRewards_unsupported_token_revert() public {
    vm.startPrank(admin);
    // Do not add rewardToken1 as supported
    vm.expectRevert(bytes('Token not supported'));
    rewardDistribution.topUpRewards(100e18, address(rewardToken1));
    vm.stopPrank();
  }

  function test_topUpRewards_when_paused_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(admin, 1000e18);
    rewardToken1.approve(address(rewardDistribution), 1000e18);
    rewardDistribution.pause();
    vm.expectRevert('Pausable: paused');
    rewardDistribution.topUpRewards(500e18, address(rewardToken1));
    vm.stopPrank();
  }

  function test_topUpRewards_non_admin_revert() public {
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.topUpRewards(100e18, address(rewardToken1));
    vm.stopPrank();
  }

  // === 6. Claim Reward Tests ===

  function test_claimReward_success() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    vm.stopPrank();

    // Create distribution
    vm.startPrank(admin);
    uint256 distributionTime = block.timestamp + 100;
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, distributionTime);
    bytes32 distributionId = keccak256(
      abi.encodePacked(uint256(1000e18), distributionTime, block.timestamp)
    );
    vm.stopPrank();

    // Allocate shares
    vm.startPrank(admin);
    rewardDistribution.allocateShares(shareholder1, 500e18);
    vm.stopPrank();

    // Fast-forward time
    vm.warp(block.timestamp + 101);

    // Claim reward
    vm.startPrank(shareholder1);
    vm.expectEmit(true, false, false, true);
    emit RewardsClaimed(shareholder1, 500e18, address(rewardToken1), distributionId);
    rewardDistribution.claimReward(distributionId);
    vm.stopPrank();

    // Verify reward balance
    assertEq(
      rewardToken1.balanceOf(shareholder1),
      500e18,
      'Shareholder should have received 500e18 tokens'
    );
  }

  function test_claimReward_before_distribution_time_revert() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    bytes32 distributionId = keccak256(
      abi.encodePacked(uint256(1000e18), block.timestamp + 100, block.timestamp)
    );
    rewardDistribution.allocateShares(shareholder1, 500e18);
    vm.stopPrank();

    // Attempt to claim before distribution time
    vm.startPrank(shareholder1);
    vm.expectRevert(bytes('Rewards not yet claimable'));
    rewardDistribution.claimReward(distributionId);
    vm.stopPrank();
  }

  function test_claimReward_already_claimed_revert() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    bytes32 distributionId = keccak256(
      abi.encodePacked(uint256(1000e18), block.timestamp + 100, block.timestamp)
    );
    rewardDistribution.allocateShares(shareholder1, 500e18);
    vm.stopPrank();

    // Fast-forward time and claim
    vm.warp(block.timestamp + 101);
    vm.startPrank(shareholder1);
    rewardDistribution.claimReward(distributionId);

    // Attempt to claim again
    vm.expectRevert(bytes('Rewards already claimed for this distribution'));
    rewardDistribution.claimReward(distributionId);
    vm.stopPrank();
  }

  function test_claimReward_when_locked_revert() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    bytes32 distributionId = keccak256(
      abi.encodePacked(uint256(1000e18), block.timestamp + 100, block.timestamp)
    );
    rewardDistribution.allocateShares(shareholder1, 500e18);
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();

    // Fast-forward time
    vm.warp(block.timestamp + 101);

    // Attempt to claim
    vm.startPrank(shareholder1);
    vm.expectRevert(bytes('Shareholder is locked'));
    rewardDistribution.claimReward(distributionId);
    vm.stopPrank();
  }

  // === 7. Claim All Rewards Tests ===

  function test_claimAllRewards_success() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardDistribution.addRewardToken(address(rewardToken2));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardToken2.mint(address(rewardDistribution), 2000e18);

    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    bytes32 distributionId1 = keccak256(
      abi.encodePacked(uint256(1000e18), block.timestamp + 100, block.timestamp)
    );
    rewardDistribution.createDistribution(address(rewardToken2), 2000e18, block.timestamp + 200);
    bytes32 distributionId2 = keccak256(
      abi.encodePacked(uint256(1000e18), block.timestamp + 200, block.timestamp)
    );
    rewardDistribution.allocateShares(shareholder1, 500e18);
    vm.stopPrank();

    // Fast-forward time
    vm.warp(block.timestamp + 201);

    // Claim all rewards
    vm.startPrank(shareholder1);
    vm.expectEmit(true, false, false, true);
    emit RewardsClaimed(shareholder1, 500e18, address(rewardToken1), distributionId1);
    vm.expectEmit(true, false, false, true);
    emit RewardsClaimed(shareholder1, 1000e18, address(rewardToken2), distributionId2);
    rewardDistribution.claimAllRewards();
    vm.stopPrank();

    // Verify reward balances
    assertEq(
      rewardToken1.balanceOf(shareholder1),
      500e18,
      'Shareholder should have received 500e18 RT1'
    );
    assertEq(
      rewardToken2.balanceOf(shareholder1),
      1000e18,
      'Shareholder should have received 1000e18 RT2'
    );
  }

  function test_claimAllRewards_when_locked_revert() public {
    // Setup
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    // bytes32 distributionId = keccak256(abi.encodePacked(uint256(1000e18), block.timestamp + 100, block.timestamp));
    rewardDistribution.allocateShares(shareholder1, 500e18);
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();

    // Fast-forward time
    vm.warp(block.timestamp + 101);

    // Attempt to claim all
    vm.startPrank(shareholder1);
    vm.expectRevert(bytes('Shareholder is locked'));
    rewardDistribution.claimAllRewards();
    vm.stopPrank();
  }

  // === 8. Lock/Unlock Rewards Tests ===

  function test_lockRewards_success() public {
    vm.startPrank(admin);
    vm.expectEmit(true, false, false, true);
    emit RewardsLocked(shareholder1);
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();

    assertTrue(
      rewardDistribution.rewardsLocked(shareholder1),
      'Rewards should be locked for shareholder1'
    );
  }

  function test_lockRewards_already_locked_revert() public {
    vm.startPrank(admin);
    rewardDistribution.lockRewards(shareholder1);
    vm.expectRevert(bytes('Rewards already locked'));
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();
  }

  function test_unlockRewards_success() public {
    // Lock first
    vm.startPrank(admin);
    rewardDistribution.lockRewards(shareholder1);
    vm.expectEmit(true, false, false, true);
    emit RewardsUnlocked(shareholder1);
    rewardDistribution.unlockRewards(shareholder1);
    vm.stopPrank();

    assertFalse(
      rewardDistribution.rewardsLocked(shareholder1),
      'Rewards should be unlocked for shareholder1'
    );
  }

  function test_unlockRewards_not_locked_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(bytes('Rewards not locked'));
    rewardDistribution.unlockRewards(shareholder1);
    vm.stopPrank();
  }

  function test_lockRewards_non_admin_revert() public {
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();
  }

  function test_unlockRewards_non_admin_revert() public {
    // Lock first
    vm.startPrank(admin);
    rewardDistribution.lockRewards(shareholder1);
    vm.stopPrank();

    // Attempt to unlock by non-admin
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.unlockRewards(shareholder1);
    vm.stopPrank();
  }

  // === 9. Create Distribution Tests ===

  function test_createDistribution_success() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);

    uint256 distributionTime_1 = block.timestamp + 100;
    vm.expectEmit(true, false, false, true);
    bytes32 distributionId = keccak256(
      abi.encodePacked(uint256(1000e18), distributionTime_1, block.timestamp)
    );
    emit RewardsDistributed(distributionId, 1000e18);

    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, distributionTime_1);
    vm.stopPrank();

    (address rewardToken, uint256 totalRewards, uint256 distributionTime) = rewardDistribution
      .getDistribution(distributionId);
    assertEq(totalRewards, 1000e18, 'Total rewards should be 1000e18');
    assertEq(distributionTime, distributionTime, 'Distribution time should be set correctly');
    assertEq(rewardToken, address(rewardToken1), 'Reward token should be set correctly');
  }

  function test_createDistribution_zero_rewards_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    vm.expectRevert(bytes('Invalid reward amount'));
    rewardDistribution.createDistribution(address(rewardToken1), 0, block.timestamp + 100);
    vm.stopPrank();
  }

  function test_createDistribution_past_distribution_time_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    vm.expectRevert(bytes('Distribution time must be in the future'));
    rewardDistribution.createDistribution(address(rewardToken1), 500e18, block.timestamp - 10);
    vm.stopPrank();
  }

  function test_createDistribution_insufficient_funds_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 500e18);
    vm.expectRevert(bytes('Insufficient funds'));
    rewardDistribution.createDistribution(address(rewardToken1), 1000e18, block.timestamp + 100);
    vm.stopPrank();
  }

  function test_createDistribution_when_paused_revert() public {
    vm.startPrank(admin);
    rewardDistribution.addRewardToken(address(rewardToken1));
    rewardToken1.mint(address(rewardDistribution), 1000e18);
    rewardDistribution.pause();
    vm.expectRevert('Pausable: paused');
    rewardDistribution.createDistribution(address(rewardToken1), 500e18, block.timestamp + 100);
    vm.stopPrank();
  }

  function test_createDistribution_non_admin_revert() public {
    vm.startPrank(nonAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE)
    );
    rewardDistribution.createDistribution(address(rewardToken1), 500e18, block.timestamp + 100);
    vm.stopPrank();
  }

  // === 10. Pause/Unpause Tests ===

  function test_pause_success() public {
    vm.startPrank(superAdmin);
    vm.expectEmit(true, false, false, true);
    emit Paused(superAdmin);
    rewardDistribution.pause();
    vm.stopPrank();

    assertTrue(rewardDistribution.paused(), 'Contract should be paused');
  }

  function test_pause_non_admin_revert() public {
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, admin, DEFAULT_ADMIN_ROLE)
    );
    rewardDistribution.pause();
    vm.stopPrank();
  }

  function test_unpause_success() public {
    // First, pause the contract
    vm.startPrank(superAdmin);
    rewardDistribution.pause();
    vm.expectEmit(true, false, false, true);
    emit Unpaused(superAdmin);
    rewardDistribution.unpause();
    vm.stopPrank();

    assertFalse(rewardDistribution.paused(), 'Contract should be unpaused');
  }

  function test_unpause_non_admin_revert() public {
    // First, pause the contract
    vm.startPrank(superAdmin);
    rewardDistribution.pause();
    vm.stopPrank();

    // Attempt to unpause by non-admin
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, admin, DEFAULT_ADMIN_ROLE)
    );
    rewardDistribution.unpause();
    vm.stopPrank();
  }

  // === 11. Upgradeability Tests ===

  function test_upgradeToV2_success() public {
    // Upgrade the contract
    vm.startPrank(superAdmin);
    Upgrades.upgradeProxy(rewardDistributionProxy, 'RewardDistributionV2.sol:RewardDistributionV2');
    RewardDistributionV2 v2_impl = RewardDistributionV2(rewardDistributionProxy);
    vm.stopPrank();

    // Verify upgrade by calling a new function from V2
    RewardDistributionV2 upgradedContract = RewardDistributionV2(rewardDistributionProxy);
    upgradedContract.setNewVariable(12345);
    assertEq(upgradedContract.getNewVariable(), 12345, 'New variable should be set correctly');
  }

  // function test_upgradeToV2_non_admin_revert() public {
  //     // Deploy V2 Implementation
  //     RewardDistributionV2 v2_impl = new RewardDistributionV2();

  //     // Attempt to upgrade by non-admin
  //     vm.startPrank(admin);
  //     vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, admin, DEFAULT_ADMIN_ROLE));
  //     _upgradeProxy(rewardDistributionProxy, "RewardDistributionV2.sol:RewardDistributionV2");
  //     vm.stopPrank();
  // }

  // // help functions here
  // function _upgradeProxy(address _proxy, string memory _newImplementation) internal {
  //     Upgrades.upgradeProxy(_proxy, _newImplementation);
  // }
}

// Mock V2 Implementation for Upgradeability Test
/// @custom:oz-upgrades-from RewardDistribution.sol:RewardDistribution
contract RewardDistributionV2 is RewardDistribution {
  uint256 private newVariable;

  function setNewVariable(uint256 _value) external {
    newVariable = _value;
  }

  function getNewVariable() external view returns (uint256) {
    return newVariable;
  }
}
