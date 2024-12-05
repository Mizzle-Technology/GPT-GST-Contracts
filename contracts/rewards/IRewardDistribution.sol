// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';

/**
 * @title IRewardDistribution
 * @notice Interface for the reward distribution contract that handles share-based reward distributions
 * @dev This interface defines the core functionality for managing shares and distributing rewards
 *
 * @dev Key Features:
 * - Share allocation and adjustment
 * - Reward token management
 * - Reward distribution scheduling
 * - Reward claiming
 * - Reward locking/unlocking
 *
 * @dev Share System:
 * - Shareholders are allocated shares that determine their proportion of rewards
 * - Shares can be adjusted by authorized roles
 * - Share amounts affect reward calculations
 *
 * @dev Reward Distribution:
 * - Multiple reward tokens can be supported
 * - Distributions are scheduled with specific tokens and amounts
 * - Rewards are claimable after distribution time
 * - Rewards can be locked/unlocked per shareholder
 *
 * @dev Usage:
 * ```solidity
 * // Create a distribution
 * rewardDistribution.createDistribution(
 *   rewardToken,
 *   totalRewards,
 *   distributionTime
 * );
 *
 * // Claim rewards
 * rewardDistribution.claimReward(distributionId);
 * ```
 */
interface IRewardDistribution {
  /// @notice Struct to hold information about a shareholder
  struct Shareholder {
    uint256 shares; // number of shares held by the shareholder
    bool isLocked; // if true, rewards are locked for this shareholder
    bool isActivated; // if true, the shareholder is active
  }

  /// @notice Struct to hold information about a distribution
  struct Distribution {
    address rewardToken; // Token used for rewards
    uint256 totalRewards; // Total rewards in this distribution
    uint256 distributionTime; // Time when rewards become claimable
    mapping(address => bool) claimed; // Tracks whether a shareholder has claimed their reward
  }

  /// @notice Event emitted when shares are allocated to a shareholder
  event SharesAllocated(address indexed account, uint256 shares);
  /// @notice Event emitted when shares are adjusted for a shareholder
  event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
  /// @notice Event emitted when rewards are topped up
  event RewardToppedUp(uint256 amount);
  /// @notice Event emitted when rewards are claimed
  event RewardsClaimed(
    address indexed account,
    uint256 amount,
    address token,
    bytes32 distributionId
  );
  /// @notice Event emitted when rewards are locked for a shareholder
  event RewardsLocked(address indexed account);
  /// @notice Event emitted when rewards are unlocked for a shareholder
  event RewardsUnlocked(address indexed account);
  /// @notice Event emitted when rewards are distributed
  event RewardsDistributed(bytes32 distributionId, uint256 amount);
  /// @notice Event emitted when a shareholder is removed
  event ShareholderRemoved(address indexed account);
  /// @notice Event emitted when a reward token is added
  event RewardTokenAdded(address indexed rewardToken);
  /// @notice Event emitted when a reward token is removed
  event RewardTokenRemoved(address indexed rewardToken);

  // Share Management
  /// @notice Sets the number of shares for a shareholder
  function setShares(address account, uint256 newShares) external;

  // Rewards Management
  /// @notice Top up rewards for a distribution
  function topUpRewards(uint256 amount, address token) external;
  /// @notice Claim rewards for a distribution
  function claimReward(bytes32 distributionId) external;
  /// @notice Claim all rewards for a shareholder
  function claimAllRewards() external;
  /// @notice Add a reward token
  function addRewardToken(address token) external;
  /// @notice Remove a reward token
  function removeRewardToken(address token) external;
  /// @notice Check if a token is a reward token
  function isRewardToken(address token) external view returns (bool);

  // Lock/Unlock Rewards
  /// @notice Lock rewards for a shareholder
  function lockRewards(address user) external;
  /// @notice Unlock rewards for a shareholder
  function unlockRewards(address user) external;

  // Distribution Schedule
  /// @notice Create a distribution
  function createDistribution(
    address token,
    uint256 totalRewards,
    uint256 distributionTime
  ) external;
  /// @notice Get distribution information
  function getDistribution(
    bytes32 distributionId
  ) external view returns (address rewardToken, uint256 totalRewards, uint256 distributionTime);

  // Pause Functions
  /// @notice Pause the contract
  function pause() external;
  /// @notice Unpause the contract
  function unpause() external;

  /// @notice Get shareholder information
  function shareholders(
    address
  ) external view returns (uint256 shares, bool isLocked, bool isActivated);
}
