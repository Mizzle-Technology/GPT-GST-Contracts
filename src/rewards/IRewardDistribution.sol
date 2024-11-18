// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IRewardDistribution {
    // Events
    event SharesAllocated(address indexed account, uint256 shares);
    event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
    event RewardToppedUp(uint256 amount);
    event RewardsClaimed(address indexed account, uint256 amount);
    event RewardsLocked(address indexed account);
    event RewardsUnlocked(address indexed account);
    event RewardsDistributed(bytes32 distributionId, uint256 amount);
    event ShareholderRemoved(address indexed account);

    // Share Management
    function allocateShares(address account, uint256 shares) external;
    function updateShareholderShares(address account, uint256 newShares) external;

    // Rewards Management
    function topUpRewards(uint256 amount) external;
    function claimRewards(bytes32 distributionId) external;
    function claimAllRewards() external;

    // Lock/Unlock Rewards
    function lockRewards(address user) external;
    function unlockRewards(address user) external;

    // Distribution Schedule
    function createDistribution(uint256 totalRewards, uint256 distributionTime) external;

    // Pause Functions
    function pause() external;
    function unpause() external;

    // View Functions
    function rewardToken() external view returns (ERC20Upgradeable);
    function totalShares() external view returns (uint256);
    function shareholders(address) external view returns (uint256 shares, bool isLocked, bool isActivated);
    function rewardsClaimed(address) external view returns (uint256);
    function rewardsLocked(address) external view returns (bool);
    function distributions(bytes32) external view returns (uint256 totalRewards, uint256 distributionTime);
}
