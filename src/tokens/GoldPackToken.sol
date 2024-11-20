// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Core functionality
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

// Local imports
import "../vault/BurnVault.sol";

/**
 * @title IGoldPackToken
 * @notice Interface for GoldPackToken
 */
interface IGoldPackToken {
    // Events for token minting and burning
    event Mint(address indexed to, uint256 amount);
    event BurnVaultSet(address indexed burnVault);

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
    function burnFromVault(address _account, uint256 _amount) external;
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
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IGoldPackToken
{
    // Admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Sales role for minting tokens
    bytes32 public constant SALES_ROLE = keccak256("SALES_ROLE");

    BurnVault public burnVault;

    // Define the customer decimals for the token
    uint8 public constant DECIMALS = 6;

    // 1 Troy ounce = 10000 GPT tokens
    uint256 public constant TOKENS_PER_TROY_OUNCE = 10000;
    uint256 public constant BURN_DELAY = 7 days;

    //private
    uint256[50] private __gap;

    /**
     * @dev Initializes the contract with the specified roles.
     * @param _super The address of the super admin
     * @param _admin The address of the admin
     * @param _sales_manager The address of the sales manager
     * Requirements:
     * - _super, _admin, and _sales_manager cannot be the zero address
     */
    function initialize(address _super, address _admin, address _sales_manager) public initializer {
        __ERC20_init("Gold Pack Token", "GPT");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(_super);

        _grantRole(DEFAULT_ADMIN_ROLE, _super);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(SALES_ROLE, _sales_manager);
        _setRoleAdmin(SALES_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
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
    function mint(address to, uint256 amount) external override whenNotPaused onlyRole(SALES_ROLE) {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    // == Burn Vault Functions ==

    function setBurnVault(address _burnVault) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_burnVault != address(0), "GoldPackToken: burn vault cannot be the zero address");
        burnVault = BurnVault(_burnVault);

        emit BurnVaultSet(_burnVault);
    }

    /**
     * @dev Deposits tokens to the burn vault for delayed burning.
     * @param amount The amount of tokens to deposit
     * Requirements:
     * - Amount must be a multiple of TOKENS_PER_TROY_OUNCE (10000)
     * - Amount must be greater than 0
     */
    function depositToBurnVault(uint256 amount) external override nonReentrant whenNotPaused {
        require(amount > 0, "GoldPackToken: amount must be greater than 0");
        require(amount % TOKENS_PER_TROY_OUNCE == 0, "GoldPackToken: amount must be a whole number of Troy ounces");

        // Transfer tokens to burn vault
        burnVault.depositTokens(msg.sender, amount, ERC20BurnableUpgradeable(address(this)));
    }

    /**
     * @dev Burns All tokens from the burn vault.
     * @param _account The account whose tokens to burn
     * Requirements:
     * - Caller must have SALES_ROLE
     * - Account must have tokens in vault
     */
    function burnFromVault(address _account) external override nonReentrant whenNotPaused onlyRole(SALES_ROLE) {
        require(_account != address(0), "GoldPackToken: account cannot be the zero address");
        ERC20BurnableUpgradeable token = ERC20BurnableUpgradeable(address(this));
        burnVault.burnAllTokens(_account, token);
    }

    /**
     * @dev Burns a specified amount of tokens from the burn vault.
     * @param _account The account whose tokens to burn
     * @param _amount The amount of tokens to burn
     * Requirements:
     * - Caller must have SALES_ROLE
     * - Account must have enough tokens in vault
     * - Amount must be a multiple of TOKENS_PER_TROY_OUNCE (10000)
     * - Amount must be greater than 0
     */
    function burnFromVault(address _account, uint256 _amount)
        external
        override
        nonReentrant
        whenNotPaused
        onlyRole(SALES_ROLE)
    {
        require(_amount > 0, "GoldPackToken: amount must be greater than zero");
        require(_amount % TOKENS_PER_TROY_OUNCE == 0, "GoldPackToken: amount must be a whole number of Troy ounces");
        require(_account != address(0), "GoldPackToken: account cannot be the zero address");

        ERC20BurnableUpgradeable token = ERC20BurnableUpgradeable(address(this));
        burnVault.burnTokens(_account, _amount, token);
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

    /**
     * @dev Checks if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return bool true if the contract supports the interface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ERC20BurnableUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    // === UUPS Upgrade ===
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
