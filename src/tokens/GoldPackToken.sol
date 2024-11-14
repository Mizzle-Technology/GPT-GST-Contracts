// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Core functionality
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// Local imports
import "../vault/BurnVault.sol";

/**
 * @title IGoldPackToken
 * @notice Interface for GoldPackToken
 */
interface IGoldPackToken {
    // Events for token minting and burning
    event Mint(address indexed to, uint256 amount);
    event VaultDeposit(address indexed from, uint256 amount);
    event VaultBurn(address indexed account, uint256 amount);

    // Events for role management
    event AdminRoleGranted(address indexed account);
    event AdminRoleRevoked(address indexed account);
    event SalesRoleGranted(address indexed account);
    event SalesRoleRevoked(address indexed account);

    // Events for pausing and unpausing
    event Paused(address account, string reason, uint256 timestamp);
    event Unpaused(address account, string reason, uint256 timestamp);

    // Functions declarations
    function mint(address to, uint256 amount) external;
    function depositToBurnVault(uint256 amount) external;
    function burnFromVault(address account) external;
    function getBurnVaultAddress() external view returns (address);
}

/**
 * @title GoldPackToken
 * @author Felix, Kun, and Andrew
 * @notice Gold-backed ERC20 token with 1 GPT = 1/10000 Troy ounce of gold
 * @dev Implementation details:
 * - Role-based access control for admin functions
 * - Burning restricted to whole Troy ounce increments
 * - Integration with BurnVault for controlled token burning
 */
contract GoldPackToken is
    ERC20Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC20BurnableUpgradeable,
    IGoldPackToken
{
    // Admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Sales role for minting tokens
    bytes32 public constant SALES_ROLE = keccak256("SALES_ROLE");

    BurnVault public burnVault;

    // 1 Troy ounce = 10000 GPT tokens
    uint256 public constant TOKENS_PER_TROY_OUNCE = 10000;
    uint256 public constant BURN_DELAY = 7 days;

    /**
     * @dev Initializes the contract, setting the deployer as the initial owner and admin.
     * @param burnVaultAddress The address of the burn vault contract that will handle token burning.
     */
    function initialize(address burnVaultAddress) public initializer {
        require(burnVaultAddress != address(0), "Invalid burn vault address");

        __ERC20_init("Gold Pack Token", "GPT");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        burnVault = BurnVault(burnVaultAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SALES_ROLE, msg.sender);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function pause(string memory reason) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        emit Paused(msg.sender, reason, block.timestamp);
    }

    function unpause(string memory reason) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        emit Unpaused(msg.sender, reason, block.timestamp);
    }

    /**
     * @dev Mints tokens to the specified address.
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint (1 GPT = 1/10000 Troy ounce)
     * Requirements:
     * - Only callable by owner
     */
    function mint(address to, uint256 amount) public override onlyRole(SALES_ROLE) whenNotPaused {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /**
     * @dev Deposits tokens to the burn vault for delayed burning.
     * @param amount The amount of tokens to deposit
     * Requirements:
     * - Amount must be a multiple of TOKENS_PER_TROY_OUNCE (10000)
     * - Amount must be greater than 0
     */
    function depositToBurnVault(uint256 amount) public override nonReentrant whenNotPaused {
        require(amount > 0, "GoldPackToken: amount must be greater than 0");
        require(amount % TOKENS_PER_TROY_OUNCE == 0, "GoldPackToken: amount must be a whole number of Troy ounces");

        // Transfer tokens to burn vault
        _transfer(msg.sender, address(burnVault), amount);
        burnVault.depositTokens(msg.sender, amount);
        emit VaultDeposit(msg.sender, amount);
    }

    /**
     * @dev Burns tokens from the burn vault.
     * @param account The account whose tokens to burn
     * Requirements:
     * - Caller must have SALES_ROLE
     * - Account must have tokens in vault
     */
    function burnFromVault(address account) public override nonReentrant onlyRole(SALES_ROLE) {
        uint256 balance = burnVault.getBalance(account);
        require(balance > 0, "GoldPackToken: no tokens in vault");

        burnVault.burnTokens(account);
        emit VaultBurn(account, balance);
    }

    /**
     * @dev Returns the address of the burn vault
     * @return Address of the burn vault contract
     */
    function getBurnVaultAddress() public view override returns (address) {
        return address(burnVault);
    }

    function isAdmin(address account) public view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    /**
     * @dev Checks if an account has sales role
     * @param account Address to check
     * @return bool true if account has sales role
     */
    function isSales(address account) public view returns (bool) {
        return hasRole(SALES_ROLE, account);
    }
}
