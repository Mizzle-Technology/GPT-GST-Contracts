// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Core functionality
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';

// Local imports
import '../vaults/BurnVault.sol';
import './IGoldPackToken.sol';

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
  ERC20PermitUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable,
  IGoldPackToken
{
  // Admin role
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  // Sales role for minting tokens
  bytes32 public constant SALES_ROLE = keccak256('SALES_ROLE');

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
    if (_super == address(0) || _admin == address(0) || _sales_manager == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    __ERC20_init('GoldPack Token', 'GPT');
    __ERC20Burnable_init();
    __AccessControl_init();
    __ReentrancyGuard_init();
    __ERC20Permit_init('Gold Pack Token');
    __Pausable_init();
    __UUPSUpgradeable_init();
    __Ownable_init(_super);

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _grantRole(SALES_ROLE, _sales_manager);
    _setRoleAdmin(SALES_ROLE, DEFAULT_ADMIN_ROLE);
  }

  function decimals() public pure override returns (uint8) {
    return DECIMALS;
  }

  /**
   * @dev Custom Modifier to check if caller has SALES_ROLE
   */
  modifier onlySalesRole() {
    if (!hasRole(SALES_ROLE, msg.sender)) {
      revert Errors.SalesRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @dev Custom Modifier to check if caller has ADMIN_ROLE
   */
  modifier onlyAdminRole() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  modifier onlyDefaultAdminRole() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @dev Mints tokens to the specified address.
   * @param to The address to mint tokens to
   * @param amount The amount of tokens to mint (1 GPT = 1/10000 Troy ounce)
   * Requirements:
   * - Only callable by owner
   */
  function mint(
    address to,
    uint256 amount
  ) external override nonReentrant whenNotPaused onlySalesRole {
    _mint(to, amount);
    emit Mint(to, amount);
  }

  // == Burn Vault Functions ==

  function setBurnVault(address _burnVault) external whenNotPaused onlyDefaultAdminRole {
    if (_burnVault == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (address(burnVault) == _burnVault) {
      revert Errors.BurnVaultAlreadySet(_burnVault);
    }
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
    require(amount > 0, 'GoldPackToken: amount must be greater than 0');
    require(
      amount % TOKENS_PER_TROY_OUNCE == 0,
      'GoldPackToken: amount must be a whole number of Troy ounces'
    );

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
  function redeemAllCoins(
    address _account
  ) external override nonReentrant whenNotPaused onlySalesRole {
    require(_account != address(0), 'GoldPackToken: account cannot be the zero address');
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
  function redeemCoins(
    address _account,
    uint256 _amount
  ) external override nonReentrant whenNotPaused onlySalesRole {
    require(_amount > 0, 'GoldPackToken: amount must be greater than zero');
    require(
      _amount % TOKENS_PER_TROY_OUNCE == 0,
      'GoldPackToken: amount must be a whole number of Troy ounces'
    );
    require(_account != address(0), 'GoldPackToken: account cannot be the zero address');

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
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(AccessControlUpgradeable) returns (bool) {
    return
      interfaceId == type(ERC20BurnableUpgradeable).interfaceId ||
      super.supportsInterface(interfaceId);
  }

  // === Pausable ===
  function pause() external virtual whenNotPaused onlyAdminRole {
    _pause();
  }

  function unpause() external virtual whenPaused onlyAdminRole {
    _unpause();
  }

  // === UUPS Upgrade ===
  function _authorizeUpgrade(
    address newImplementation
  ) internal view override onlyDefaultAdminRole {}

  // Add role revocation functions
  function revokeSalesRole(address _account) external onlyDefaultAdminRole {
    revokeRole(SALES_ROLE, _account);
  }

  function revokeAdminRole(address _account) external onlyDefaultAdminRole {
    revokeRole(ADMIN_ROLE, _account);
  }

  // Add emergency withdrawal function
  function emergencyWithdraw(
    address token,
    address to,
    uint256 amount
  ) external onlyDefaultAdminRole whenPaused {
    if (token == address(this)) {
      revert Errors.CannotWithdrawGptTokens();
    }
    ERC20Upgradeable(token).transfer(to, amount);
  }
}
