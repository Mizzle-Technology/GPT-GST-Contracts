// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Core functionality
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

// Access Control
import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";

// Proxy/Upgrade
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Local imports
import "./BurnVault.sol";

/**
 * @title GoldPackToken
 * @author Felix, Kun, and Andrew
 * @notice Gold-backed ERC20 token with 1 GPT = 1/10000 Troy ounce of gold
 * @dev Implementation details:
 * - Upgradeable via UUPS pattern
 * - Implements ERC20Permit for gasless transactions
 * - Role-based access control for admin functions
 * - Burning restricted to whole Troy ounce increments
 * - Integration with BurnVault for controlled token burning
 */
contract GoldPackToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    ERC20BurnableUpgradeable
{
    // Admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Sales role for minting tokens
    bytes32 public constant SALES_ROLE = keccak256("SALES_ROLE");

    BurnVault public burnVault;

    // 1 Troy ounce = 10000 GPT tokens
    uint256 public constant TOKENS_PER_TROY_OUNCE = 10000;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract, setting the deployer as the initial owner and admin.
     * @param burnVaultAddress The address of the burn vault contract that will handle token burning.
     */
    function initialize(address burnVaultAddress) public initializer {
        __ERC20_init("Gold Pack Token", "GPT");
        __ERC20Permit_init("Gold Pack Token");
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __AccessControl_init();
        __ERC20Burnable_init();

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(ADMIN_ROLE, msg.sender);
        grantRole(SALES_ROLE, msg.sender);

        burnVault = BurnVault(burnVaultAddress);
    }

    /**
     * @dev Mints tokens to the specified address.
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint (1 GPT = 1/10000 Troy ounce)
     * Requirements:
     * - Only callable by owner
     */
    function mint(address to, uint256 amount) public onlyRole(SALES_ROLE) {
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
    function depositToBurnVault(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount % TOKENS_PER_TROY_OUNCE == 0,
            "Amount must be a whole number of Troy ounces (10000 GPT per Troy ounce)"
        );

        _transfer(msg.sender, address(burnVault), amount);
        burnVault.depositTokens(amount);
    }

    /**
     * @dev Burns `amount` tokens from the burn vault.
     * Can only be called by an account with the admin role.
     * @param account The account whose tokens to burn.
     */
    function burnFromVault(address account) public onlyRole(SALES_ROLE) {
        burnVault.burnTokens(account);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation.
     * Can only be called by the owner.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Emitted when tokens are minted.
     * @param to The address to which tokens are minted.
     * @param amount The amount of tokens minted.
     */
    event Mint(address indexed to, uint256 amount);

    /**
     * @dev Emitted when tokens are burned.
     * @param from The address from which tokens are burned.
     * @param amount The amount of tokens burned.
     */
    event Burn(address indexed from, uint256 amount);

    // Events for role management
    event AdminRoleGranted(address indexed account);
    event AdminRoleRevoked(address indexed account);
    event SalesRoleGranted(address indexed account);
    event SalesRoleRevoked(address indexed account);

    // Role management functions
    /**
     * @dev Grants admin role to an account
     * @param account Address to grant admin role
     * Requirements:
     * - Only callable by owner
     */
    function grantAdminRole(address account) public onlyOwner {
        grantRole(ADMIN_ROLE, account);
        emit AdminRoleGranted(account);
    }

    /**
     * @dev Revokes admin role from an account
     * @param account Address to revoke admin role from
     * Requirements:
     * - Only callable by owner
     */
    function revokeAdminRole(address account) public onlyOwner {
        revokeRole(ADMIN_ROLE, account);
        emit AdminRoleRevoked(account);
    }

    /**
     * @dev Grants sales role to an account
     * @param account Address to grant sales role
     * Requirements:
     * - Only callable by owner or admin
     */
    function grantSalesRole(address account) public onlyRole(ADMIN_ROLE) {
        grantRole(SALES_ROLE, account);
        emit SalesRoleGranted(account);
    }

    /**
     * @dev Revokes sales role from an account
     * @param account Address to revoke sales role from
     * Requirements:
     * - Only callable by owner or admin
     */
    function revokeSalesRole(address account) public onlyRole(ADMIN_ROLE) {
        revokeRole(SALES_ROLE, account);
        emit SalesRoleRevoked(account);
    }

    /**
     * @dev Checks if an account has admin role
     * @param account Address to check
     * @return bool true if account has admin role
     */
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
