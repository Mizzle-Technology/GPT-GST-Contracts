// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../vault/TradingVault.sol";
import "./IRewardDistribution.sol";

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

    // === constants ===
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // Represents 100% shares scaled by 1e18
    uint256 public constant SCALE = 1e18;

    struct Shareholder {
        uint256 shares; // number of shares held by the shareholder
        bool isLocked; // if true, rewards are locked for this shareholder
        bool isActivated; // if true, the shareholder is active
    }

    struct Distribution {
        uint256 totalRewards; // Total rewards in this distribution
        uint256 distributionTime; // Time when rewards become claimable
        mapping(address => bool) claimed; // Tracks whether a shareholder has claimed their reward
    }

    uint256 public totalShares; // total shares allocated
    uint256[50] private __gap; // gap for upgrade safety
    ERC20Upgradeable public rewardToken; // reward token
    EnumerableSet.AddressSet private shareholderAddresses; // total number of shareholders

    // Mapping to store shareholders and their shares
    mapping(address => Shareholder) public shareholders;
    mapping(address => uint256) public rewardsClaimed; // User => Total claimed rewards
    mapping(address => bool) public rewardsLocked; // User => Whether rewards are locked
    mapping(bytes32 => Distribution) public distributions; // Distribution ID => Distribution details

    // Reward schedule variables
    uint256 public lastDistributionTime;

    function initialize(address _rewardToken, address _admin) public initializer {
        __Ownable_init(msg.sender);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, _admin);

        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = ERC20Upgradeable(_rewardToken);

        lastDistributionTime = block.timestamp;

        // Initialize totalShares to 1e18 representing 100%
        totalShares = SCALE;
    }

    // === 1. Allocate Shares ===
    /**
     * @notice Allocates shares to a shareholder.
     *
     * @param account The address of the shareholder.
     * @param shares The number of shares to allocate.
     *
     * Requirements:
     * - `account` cannot be the zero address.
     * - `shares` must be greater than zero.
     * - Total shares after allocation must not exceed `SCALE`.
     *
     * Emits a {SharesAllocated} event.
     */
    function allocateShares(address account, uint256 shares) external override onlyRole(ADMIN_ROLE) whenNotPaused {
        require(account != address(0), "Invalid account address");
        require(shares > 0, "Shares must be greater than zero");
        require(totalShares + shares <= SCALE, "Total shares exceed maximum");

        Shareholder storage shareholder = shareholders[account];

        if (shareholder.shares == 0) {
            // New shareholder, add to the array
            bool added = shareholderAddresses.add(account);
            require(added, "RewardDistribution: shareholder already exists");
            shareholder.isActivated = true;
        }

        // Add shares to the shareholder and update total shares
        shareholder.shares += shares;
        totalShares += shares;

        emit SharesAllocated(account, shares);
    }

    // === 2. Adjust Shares ===
    /**
     * @notice Updates the shares of a shareholder.
     *
     * @param account The address of the shareholder.
     * @param newShares The new number of shares to allocate.
     *
     * Requirements:
     * - `account` cannot be the zero address.
     * - `newShares` must not cause `totalShares` to exceed `SCALE`.
     */
    function updateShareholderShares(address account, uint256 newShares)
        external
        override
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        // === Checks ===
        require(account != address(0), "RewardDistribution: invalid account address");

        Shareholder storage shareholder = shareholders[account];
        uint256 oldShares = shareholder.shares;

        // Calculate new total shares and validate
        uint256 updatedTotalShares = totalShares - oldShares + newShares;
        require(updatedTotalShares <= SCALE, "RewardDistribution: total shares exceed maximum");

        // === Effects ===
        if (oldShares == 0 && newShares > 0) {
            // New shareholder, add to the array
            bool added = shareholderAddresses.add(account);
            require(added, "RewardDistribution: shareholder already exists");
            shareholder.isActivated = true;
        }

        // Update shares and totalShares
        shareholder.shares = newShares;
        totalShares = updatedTotalShares;

        // Handle deactivation and removal
        if (newShares == 0 && oldShares > 0) {
            bool removed = shareholderAddresses.remove(account);
            require(removed, "RewardDistribution: failed to remove shareholder");
            shareholder.isActivated = false;
            emit ShareholderRemoved(account);
        }

        // === Interactions ===
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
    function claimRewards(bytes32 distributionId) external override nonReentrant whenNotPaused {
        Distribution storage distribution = distributions[distributionId];
        require(!distribution.claimed[msg.sender], "Rewards already claimed for this distribution");
        require(!rewardsLocked[msg.sender], "Rewards are locked for this user");

        Shareholder storage shareholder = shareholders[msg.sender];
        require(shareholder.shares > 0, "No shares assigned");

        // Calculate the user's share of the rewards
        uint256 userShareAmount = (shareholder.shares * distribution.totalRewards) / SCALE;

        // Mark rewards as claimed for this distribution
        distribution.claimed[msg.sender] = true;

        // Transfer tokens to the user
        rewardToken.safeTransfer(msg.sender, userShareAmount);

        emit RewardsClaimed(msg.sender, userShareAmount);
    }

    function claimAllRewards() external override nonReentrant whenNotPaused {
        require(!rewardsLocked[msg.sender], "Rewards are locked for this user");

        Shareholder storage shareholder = shareholders[msg.sender];
        require(shareholder.shares > 0, "No shares assigned");

        uint256 totalClaimableRewards = 0;

        for (uint256 i = 0; i < shareholderAddresses.length(); i++) {
            bytes32 distributionId = keccak256(abi.encodePacked(i)); // Assuming unique distribution IDs
            Distribution storage distribution = distributions[distributionId];

            if (!distribution.claimed[msg.sender]) {
                uint256 userShareAmount = (shareholder.shares * distribution.totalRewards) / SCALE;
                distribution.claimed[msg.sender] = true; // Mark as claimed
                totalClaimableRewards += userShareAmount;
            }
        }

        require(totalClaimableRewards > 0, "No rewards available to claim");

        // Transfer all claimable rewards in a single transaction
        rewardToken.safeTransfer(msg.sender, totalClaimableRewards);

        emit RewardsClaimed(msg.sender, totalClaimableRewards);
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
    function unlockRewards(address user) external override onlyRole(ADMIN_ROLE) {
        require(rewardsLocked[user], "Rewards not locked");
        rewardsLocked[user] = false;
        emit RewardsUnlocked(user);
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
    function createDistribution(uint256 totalRewards, uint256 distributionTime)
        external
        override
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        require(totalRewards > 0, "Invalid reward amount");
        require(distributionTime > block.timestamp, "Distribution time must be in the future");
        require(rewardToken.balanceOf(address(this)) >= totalRewards, "Insufficient funds");

        bytes32 distributionId = keccak256(abi.encodePacked(totalRewards, distributionTime, block.timestamp));

        distributions[distributionId].totalRewards = totalRewards;
        distributions[distributionId].distributionTime = distributionTime;

        emit RewardsDistributed(distributionId, totalRewards);
    }

    // === Pause Functions ===

    /**
     * @notice Pauses the contract, disabling certain functionalities.
     *
     * Requirements:
     * - Only accounts with ADMIN_ROLE can call.
     */
    function pause() external override onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, enabling previously disabled functionalities.
     *
     * Requirements:
     * - Only accounts with ADMIN_ROLE can call.
     */
    function unpause() external override onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // === Upgradeability ===
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
