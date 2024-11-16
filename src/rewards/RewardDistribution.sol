// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // === constants ===
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // Represents 100% shares scaled by 1e18
    uint256 public constant SCALE = 1e18;

    struct Shareholder {
        uint256 shares; // number of shares held by the shareholder
        uint256 rewardDebt; // timestamp of the last reward claim
        bool isLocked; // if true, rewards are locked for this shareholder
    }

    struct RewardsInfo {

    }

    uint256 public totalRewards;
    uint256 public totalShares;

    // Mapping to store shareholders and their shares
    mapping(address => Shareholder) public shareholders;
    mapping(address => uint256) public rewardsClaimed; // User => Total claimed rewards
    mapping(address => bool) public rewardsLocked; // User => Whether rewards are locked

    IERC20 public rewardToken;

    // Reward schedule variables
    uint256 public lastDistributionTime;
    uint256 public distributionInterval; // In seconds (e.g., 1 day = 86400)

    // Events
    event SharesAllocated(address indexed account, uint256 shares);
    event SharesAdjusted(address indexed account, uint256 oldShares, uint256 newShares);
    event RewardToppedUp(uint256 amount);
    event RewardsClaimed(address indexed account, uint256 amount);
    event RewardsLocked(address indexed account);
    event RewardsUnlocked(address indexed account);
    event RewardsDistributed(uint256 amount);

    function initialize(address _rewardToken, uint256 _distributionInterval) public initializer {
        __Ownable_init(msg.sender);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IERC20(_rewardToken);

        distributionInterval = _distributionInterval;
        lastDistributionTime = block.timestamp;

        // Initialize totalShares to 1e18 representing 100%
        totalShares = SCALE;
    }

    // === 1. Allocate Shares ===
    function allocateShares(address account, uint256 shares) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(account != address(0), "Invalid account address");
        require(shares > 0, "Shares must be greater than zero");
        require(totalShares + shares <= SCALE, "Total shares exceed 100%");

        // Add shares to the shareholder and update total shares
        Shareholder storage shareholder = shareholders[account];
        shareholder.shares += shares;
        totalShares += shares;

        emit SharesAllocated(account, shares);
    }

    // === 2. Adjust Shares ===
    function adjustShares(address account, uint256 newShares) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(account != address(0), "Invalid account address");
        require(newShares > 0, "Shares must be greater than zero");

        Shareholder storage shareholder = shareholders[account];
        require(shareholder.shares > 0, "Account has no shares");

        uint256 oldShares = shareholder.shares;

        // Calculate new total shares
        uint256 updatedTotalShares = totalShares - oldShares + newShares;
        require(updatedTotalShares <= SCALE, "Total shares exceed 100%");

        // Update shares
        shareholder.shares = newShares;
        totalShares = updatedTotalShares;

        emit SharesAdjusted(account, oldShares, newShares);
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
    function topUpRewards(uint256 amount) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer reward tokens from the admin to the contract
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

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
    function claimRewards() external nonReentrant whenNotPaused {
        require(!rewardsLocked[msg.sender], "Rewards are locked for this user");

        Shareholder storage shares = shareholders[msg.sender];
        require(shares.shares > 0, "No shares assigned to user");

        // Calculate user's share proportion (scaled by SCALE)
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        uint256 userShareAmount = (shares.shares * contractBalance) / SCALE;

        // Calculate claimable rewards
        uint256 pendingRewards = userShareAmount - shares.rewardDebt;
        require(pendingRewards > 0, "No rewards available for claim");

        // Update reward debt
        shares.rewardDebt += pendingRewards;

        // Transfer rewards to the user
        rewardToken.safeTransfer(msg.sender, pendingRewards);

        emit RewardsClaimed(msg.sender, pendingRewards);
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
    function lockRewards(address user) external onlyRole(ADMIN_ROLE) {
        require(!rewardsLocked[user], "Rewards already locked");
        rewardsLocked[user] = true;
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
    function unlockRewards(address user) external onlyRole(ADMIN_ROLE) {
        require(rewardsLocked[user], "Rewards not locked");
        rewardsLocked[user] = false;
        emit RewardsUnlocked(user);
    }

    // Reward Distribution Schedule
    function distributeRewards(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(block.timestamp >= lastDistributionTime + distributionInterval, "Distribution interval not reached");
        require(amount > 0, "Invalid reward amount");

        // Transfer the reward tokens to the contract
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update the total rewards
        totalRewards += amount;

        // Update the last distribution time
        lastDistributionTime = block.timestamp;

        emit RewardsDistributed(amount);
    }

     // === Pause Functions ===

    /**
     * @notice Pauses the contract, disabling certain functionalities.
     *
     * Requirements:
     * - Only accounts with ADMIN_ROLE can call.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, enabling previously disabled functionalities.
     *
     * Requirements:
     * - Only accounts with ADMIN_ROLE can call.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // === View Functions ===

    /**
     * @notice Calculates the pending rewards for a user.
     * @param account The address to query rewards for.
     * @return The amount of pending rewards.
     */
    function pendingRewards(address account) external view returns (uint256) {
        Shareholder storage shares = shareholders[account];
        if (shares.shares == 0) {
            return 0;
        }
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        uint256 userShareAmount = (shares.shares * contractBalance) / SCALE;
        return userShareAmount - shares.rewardDebt;
    }

    // Admin Functions
    function setDistributionInterval(uint256 interval) external onlyRole(ADMIN_ROLE) {
        require(interval > 0, "Invalid interval");
        distributionInterval = interval;
    }
}
