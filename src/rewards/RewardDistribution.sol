// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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
contract RewardDistribution is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Shareholder {
        uint256 shares; // number of shares held by the shareholder
        uint256 lastClaimed; // timestamp of the last reward claim
        bool isLocked; // if true, rewards are locked for this shareholder
    }

    // Mapping to store shareholders and their shares
    mapping(address => Shareholder) public shareholders;
    uint256 public totalShares;

    IERC20 public rewardToken;

    // Events
    event SharesAllocated(address indexed account, uint256 shares);
    event SharesAdjusted(address indexed account, uint256 newShares);
    event RewardToppedUp(uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event RewardsLocked(address indexed account);
    event RewardsUnlocked(address indexed account);

    function initialize(address _rewardToken) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IERC20(_rewardToken);
    }

    // === 1. Allocate Shares ===
    function allocateShares(address account, uint256 shares) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(account != address(0), "Invalid account address");
        require(shares > 0, "Shares must be greater than zero");

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

        // Update total shares based on the new amount
        totalShares = totalShares - shareholder.shares + newShares;
        shareholder.shares = newShares;

        emit SharesAdjusted(account, newShares);
    }

    // === Rewards Management ===
    function topUpRewards(uint256 amount) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer reward tokens from the admin to the contract
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardToppedUp(amount);
    }


}
