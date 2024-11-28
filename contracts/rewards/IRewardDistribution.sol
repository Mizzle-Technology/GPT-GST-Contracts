// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';

interface IRewardDistribution {
  struct Shareholder {
    uint256 shares; // number of shares held by the shareholder
    bool isLocked; // if true, rewards are locked for this shareholder
    bool isActivated; // if true, the shareholder is active
  }

  struct Distribution {
    address rewardToken; // Token used for rewards
    uint256 totalRewards; // Total rewards in this distribution
    uint256 distributionTime; // Time when rewards become claimable
    mapping(address => bool) claimed; // Tracks whether a shareholder has claimed their reward
  }
  // Events
  event SharesAllocated(address indexed account, uint256 shares);
  event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
  event RewardToppedUp(uint256 amount);
  event RewardsClaimed(
    address indexed account,
    uint256 amount,
    address token,
    bytes32 distributionId
  );
  event RewardsLocked(address indexed account);
  event RewardsUnlocked(address indexed account);
  event RewardsDistributed(bytes32 distributionId, uint256 amount);
  event ShareholderRemoved(address indexed account);
  event RewardTokenAdded(address indexed rewardToken);
  event RewardTokenRemoved(address indexed rewardToken);

  // Share Management
  function setShares(address account, uint256 newShares) external;

  // Rewards Management
  function topUpRewards(uint256 amount, address token) external;
  function claimReward(bytes32 distributionId) external;
  function claimAllRewards() external;
  function addRewardToken(address token) external;
  function removeRewardToken(address token) external;
  function isRewardToken(address token) external view returns (bool);

  // Lock/Unlock Rewards
  function lockRewards(address user) external;
  function unlockRewards(address user) external;

  // Distribution Schedule
  function createDistribution(
    address token,
    uint256 totalRewards,
    uint256 distributionTime
  ) external;
  function getDistribution(
    bytes32 distributionId
  ) external view returns (address rewardToken, uint256 totalRewards, uint256 distributionTime);

  // Pause Functions
  function pause() external;
  function unpause() external;

  function shareholders(
    address
  ) external view returns (uint256 shares, bool isLocked, bool isActivated);
}