// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../vaults/TradingVault.sol';
import './IRewardDistribution.sol';
import '../libs/LinkedMap.sol';
import '../../utils/Errors.sol';

/**
 * @title RewardDistribution
 * @notice Contract for distributing rewards to shareholders
 * @dev Implementation details:
 * - Shareholders can allocate, adjust, and claim rewards
 * - Rewards can be topped up by the admin
 * - Rewards can be locked and unlocked by the admin
 */
contract RewardDistribution is
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable,
  PausableUpgradeable,
  IRewardDistribution
{
  using SafeERC20 for ERC20Upgradeable;
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using LinkedMap for LinkedMap.LinkedList;

  // === constants ===
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  // Represents 100% shares scaled by 1e18
  uint256 public constant SCALE = 1e18;

  uint256 public totalShares; // total shares allocated
  uint256[50] private __gap; // gap for upgrade safety
  EnumerableSet.AddressSet private shareholderAddresses; // total number of shareholders
  EnumerableSet.AddressSet private rewardTokens; // reward tokens
  LinkedMap.LinkedList private distributionList; // List of distributions

  // Mapping to store shareholders and their shares
  mapping(address => Shareholder) public shareholders;
  mapping(address => bool) public supportTokens; // Support tokens
  mapping(bytes32 => Distribution) public distributions; // Distribution ID => Distribution

  // Reward schedule variables
  uint256 public lastDistributionTime;

  function initialize(address _super, address _admin) public initializer {
    if (_super == address(0) || _admin == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    __Ownable_init(msg.sender);
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();
    __Ownable_init(_super);

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    lastDistributionTime = block.timestamp;

    // Initialize totalShares to 0%
    totalShares = 0 * SCALE;
  }

  // === Modifiers ===
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  modifier onlyDefaultAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
  }

  // === Set Shares ===
  /**
   * @notice Updates the shares of a shareholder.
   *
   * @param account The address of the shareholder.
   * @param newShares The new number of shares to allocate.
   *
   * Requirements:
   * - `account` cannot be the zero address.
   * - `newShares` must not cause `totalShares` to exceed `SCALE`.
   * Example of share allocation:
   * - 100% shares = 1 * 1e18
   * - 50% shares = 0.5 * 1e18
   * - 1% shares = 0.01 * 1e18
   * - 0.5% shares = 0.005 * 1e18
   * The formula is: percentage * 1e18 / 100
   */
  function setShares(address account, uint256 newShares) external override onlyAdmin whenNotPaused {
    // === Checks ===
    if (account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    Shareholder storage shareholder = shareholders[account];
    uint256 oldShares = shareholder.shares;

    // Calculate new total shares and validate
    uint256 updatedTotalShares = totalShares - oldShares + newShares;
    if (updatedTotalShares > SCALE) {
      revert Errors.TotalSharesExceedMaximum();
    }

    // === Effects ===
    if (oldShares == 0 && newShares > 0) {
      // New shareholder, add to the array
      bool added = shareholderAddresses.add(account);
      if (!added) {
        revert Errors.ShareholderAlreadyExists(account);
      }
      shareholder.isActivated = true;
    }

    // Update shares and totalShares
    shareholder.shares = newShares;
    totalShares = updatedTotalShares;

    // Handle deactivation and removal
    if (newShares == 0 && oldShares > 0) {
      bool removed = shareholderAddresses.remove(account);
      if (!removed) {
        revert Errors.ShareholderNotFound(account);
      }
      shareholder.isActivated = false;
      emit ShareholderRemoved(account);
    }

    // === Interactions ===
    emit SharesAdjusted(account, oldShares, newShares);
  }

  // === Support Tokens ===

  /**
   * @notice Adds a new reward token to the contract.
   * @param token The address of the reward token.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   * - The token address must not be the zero address.
   * - The token must not already be supported.
   */
  function addRewardToken(address token) external override onlyRole(ADMIN_ROLE) {
    require(token != address(0), 'Invalid token address');
    require(!supportTokens[token], 'Token already supported');

    rewardTokens.add(token);
    supportTokens[token] = true;

    emit RewardTokenAdded(token);
  }

  /**
   * @notice Removes a reward token from the contract.
   * @param token The address of the reward token.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   * - The token must be supported.
   */
  function removeRewardToken(address token) external override onlyRole(ADMIN_ROLE) {
    require(address(token) != address(0), 'Invalid token address');
    require(supportTokens[token], 'Token not supported');

    rewardTokens.remove(token);
    supportTokens[token] = false;

    emit RewardTokenRemoved(token);
  }

  // === Rewards Management ===

  /**
   * @notice Allows the admin to top up the reward pool with a specified amount of tokens.
   * @dev This function can only be called by an account with the ADMIN_ROLE, and it is protected
   *      against reentrancy attacks. The contract must not be paused when this function is called.
   * @param amount The amount of reward tokens to be added to the reward pool. Must be greater than zero.
   * require The `amount` parameter must be greater than zero.
   * require The caller must have the ADMIN_ROLE.
   * require The contract must not be paused.
   * require The function is protected against reentrancy attacks.
   * emit RewardToppedUp Emitted when the reward pool is successfully topped up with the specified amount.
   */
  function topUpRewards(
    uint256 amount,
    address token
  ) external override onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
    require(amount > 0, 'Amount must be greater than zero');
    require(supportTokens[token], 'Token not supported');

    // Transfer reward tokens from the admin to the contract
    ERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);

    emit RewardToppedUp(amount);
  }

  /**
   * @notice Allows shareholders to claim their rewards.
   *
   * Requirements:
   * - Rewards must not be locked for the caller.
   * - Caller must have shares allocated.
   * - There must be claimable rewards available.
   */
  function claimReward(bytes32 distributionId) external override nonReentrant whenNotPaused {
    Distribution storage distribution = distributions[distributionId];
    require(!distribution.claimed[msg.sender], 'Rewards already claimed for this distribution');
    require(block.timestamp >= distribution.distributionTime, 'Rewards not yet claimable');

    Shareholder storage shareholder = shareholders[msg.sender];
    if (!shareholder.isActivated) {
      revert Errors.ShareholderNotActivated(msg.sender);
    }
    if (shareholder.isLocked) {
      revert Errors.ShareholderLocked(msg.sender);
    }
    if (shareholder.shares == 0) {
      revert Errors.NoSharesAssigned(msg.sender);
    }

    uint256 rewardAmount = (distribution.totalRewards * shareholder.shares) / SCALE;
    distribution.claimed[msg.sender] = true;

    ERC20Upgradeable rewardToken = ERC20Upgradeable(distribution.rewardToken);
    rewardToken.safeTransfer(msg.sender, rewardAmount);

    emit RewardsClaimed(msg.sender, rewardAmount, distribution.rewardToken, distributionId);
  }

  function claimAllRewards() external override nonReentrant whenNotPaused {
    Shareholder storage shareholder = shareholders[msg.sender];
    if (!shareholder.isActivated) {
      revert Errors.ShareholderNotActivated(msg.sender);
    }
    if (shareholder.isLocked) {
      revert Errors.ShareholderLocked(msg.sender);
    }

    bytes32 currentId = distributionList.getHead();

    while (currentId != bytes32(0)) {
      Distribution storage distribution = distributions[currentId];
      if (!distribution.claimed[msg.sender] && block.timestamp >= distribution.distributionTime) {
        uint256 rewardAmount = (distribution.totalRewards * shareholder.shares) / SCALE;
        distribution.claimed[msg.sender] = true;

        ERC20Upgradeable rewardToken = ERC20Upgradeable(distribution.rewardToken);
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardsClaimed(msg.sender, rewardAmount, distribution.rewardToken, currentId);
      }
      currentId = distributionList.next(currentId);
    }
  }

  // === Lock/Unlock Rewards ===

  /**
   * @notice Locks rewards for a specific user.
   * @param user The address to lock rewards for.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   * - `user` cannot be the zero address.
   * - Rewards must not already be locked for the user.
   */
  function lockRewards(address user) external override onlyRole(ADMIN_ROLE) {
    if (user == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    Shareholder storage shareholder = shareholders[user];

    if (shareholder.isLocked) {
      revert Errors.RewardsAlreadyLocked(user);
    }
    shareholder.isLocked = true;

    emit RewardsLocked(user);
  }

  /**
   * @notice Unlocks rewards for a specific user.
   * @param user The address to unlock rewards for.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   * - `user` cannot be the zero address.
   * - Rewards must already be locked for the user.
   */
  function unlockRewards(address user) external override onlyRole(ADMIN_ROLE) {
    if (user == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    Shareholder storage shareholder = shareholders[user];
    if (!shareholder.isLocked) {
      revert Errors.RewardsNotLocked(user);
    }
    shareholder.isLocked = false;

    emit RewardsUnlocked(user);
  }

  function isRewardToken(address token) external view override returns (bool) {
    if (token == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    return supportTokens[token];
  }

  // Reward Distribution Schedule

  /**
   * @notice Creates a new reward distribution with the specified total rewards and distribution time.
   * @param totalRewards The total amount of rewards to be distributed.
   * @param distributionTime The time when the rewards will be distributed.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   * - The contract must not be paused.
   * - The `totalRewards` parameter must be greater than zero.
   * - The `distributionTime` parameter must be in the future.
   * - The contract must have sufficient funds to cover the reward distribution.
   */
  function createDistribution(
    address token,
    uint256 totalRewards,
    uint256 distributionTime
  ) external override onlyRole(ADMIN_ROLE) whenNotPaused {
    require(totalRewards > 0, 'Invalid reward amount');
    require(distributionTime > block.timestamp, 'Distribution time must be in the future');

    ERC20Upgradeable rewardToken = ERC20Upgradeable(token);
    require(rewardToken.balanceOf(address(this)) >= totalRewards, 'Insufficient funds');

    bytes32 distributionId = keccak256(
      abi.encodePacked(totalRewards, distributionTime, block.timestamp)
    );

    distributions[distributionId].totalRewards = totalRewards;
    distributions[distributionId].distributionTime = distributionTime;
    distributions[distributionId].rewardToken = token;

    // Add distribution to the linked list
    distributionList.add(distributionId);

    emit RewardsDistributed(distributionId, totalRewards);
  }

  // === Pause Functions ===

  /**
   * @notice Pauses the contract, disabling certain functionalities.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   */
  function pause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses the contract, enabling previously disabled functionalities.
   *
   * Requirements:
   * - Only accounts with ADMIN_ROLE can call.
   */
  function unpause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  // === Upgradeability ===
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // === View Functions ===
  function getShareholders(
    address account
  ) external view returns (uint256 shares, bool isLocked, bool isActivated) {
    if (account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    Shareholder storage shareholder = shareholders[account];
    return (shareholder.shares, shareholder.isLocked, shareholder.isActivated);
  }

  function getDistribution(
    bytes32 distributionId
  )
    external
    view
    override
    returns (address rewardToken, uint256 totalRewards, uint256 distributionTime)
  {
    Distribution storage distribution = distributions[distributionId];
    return (distribution.rewardToken, distribution.totalRewards, distribution.distributionTime);
  }
}
