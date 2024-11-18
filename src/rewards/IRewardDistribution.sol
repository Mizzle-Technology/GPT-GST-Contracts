// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IRewardDistribution {
    // Events
    event SharesAllocated(address indexed account, uint256 shares);
    event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
    event RewardToppedUp(uint256 amount);
    event RewardsClaimed(address indexed account, uint256 amount, address token, bytes32 distributionId);
    event RewardsLocked(address indexed account);
    event RewardsUnlocked(address indexed account);
    event RewardsDistributed(bytes32 distributionId, uint256 amount);
    event ShareholderRemoved(address indexed account);
    event RewardTokenAdded(address indexed rewardToken);
    event RewardTokenRemoved(address indexed rewardToken);

    // Share Management
    function allocateShares(address account, uint256 shares) external;
    function updateShareholderShares(address account, uint256 newShares) external;

    // Rewards Management
    function topUpRewards(uint256 amount, address token) external;
    function claimReward(bytes32 distributionId) external;
    function claimAllRewards() external;
    function addRewardToken(address token) external;
    function removeRewardToken(address token) external;

    // Lock/Unlock Rewards
    function lockRewards(address user) external;
    function unlockRewards(address user) external;

    // Distribution Schedule
    function createDistribution(address token, uint256 totalRewards, uint256 distributionTime) external;

    // Pause Functions
    function pause() external;
    function unpause() external;
}
