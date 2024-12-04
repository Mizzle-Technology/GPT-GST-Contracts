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

// Local imports
import './IGoldPackToken.sol';
import '../utils/Errors.sol';

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

  // Define the customer decimals for the token
  uint8 public constant DECIMALS = 6;

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

  /**
   * @dev Returns the number of decimals used by the token
   * @return The number of decimals
   */
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
   * @param _to The address to mint tokens to
   * @param _amount The amount of tokens to mint (1 GPT = 1/10000 Troy ounce)
   * Requirements:
   * - Only callable by owner
   */
  function mint(
    address _to,
    uint256 _amount
  ) external override nonReentrant whenNotPaused onlySalesRole {
    if (_to == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (_amount == 0) {
      revert Errors.AmountCannotBeZero();
    }
    _mint(_to, _amount);
    emit Mint(_to, _amount);
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

  /**
   * @dev Pauses the contract
   * @dev Only callable by admin
   */
  function pause() external virtual whenNotPaused onlyAdminRole {
    _pause();
  }

  /**
   * @dev Unpauses the contract
   * @dev Only callable by admin
   */
  function unpause() external virtual whenPaused onlyAdminRole {
    _unpause();
  }

  // === UUPS Upgrade ===

  /**
   * @dev Authorizes the upgrade to a new implementation
   * @dev Only callable by default admin
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal view override onlyDefaultAdminRole {}

  // === Role Management ===

  /**
   * @dev Grants the sales role to an account
   * @dev Only callable by default admin
   */
  function grantSalesRole(address _account) external onlyDefaultAdminRole {
    if (_account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (hasRole(SALES_ROLE, _account)) {
      revert Errors.SalesRoleAlreadyGranted(_account);
    }
    grantRole(SALES_ROLE, _account);
    emit SalesRoleGranted(_account);
  }

  /**
   * @dev Grants the admin role to an account
   * @dev Only callable by default admin
   */
  function grantAdminRole(address _account) external onlyDefaultAdminRole {
    if (_account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (hasRole(ADMIN_ROLE, _account)) {
      revert Errors.AdminRoleAlreadyGranted(_account);
    }
    grantRole(ADMIN_ROLE, _account);
    emit AdminRoleGranted(_account);
  }

  /**
   * @dev Revokes the sales role from an account
   * @dev Only callable by default admin
   */
  function revokeSalesRole(address _account) external onlyDefaultAdminRole {
    if (_account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    revokeRole(SALES_ROLE, _account);
    emit SalesRoleRevoked(_account);
  }

  /**
   * @dev Revokes the admin role from an account
   * @dev Only callable by default admin
   */
  function revokeAdminRole(address _account) external onlyDefaultAdminRole {
    if (_account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    revokeRole(ADMIN_ROLE, _account);
    emit AdminRoleRevoked(_account);
  }

  /**
   * @dev Emergency withdrawal function
   * @dev Only callable by default admin when paused
   */
  function emergencyWithdraw(
    address token,
    address to,
    uint256 amount
  ) external onlyDefaultAdminRole whenPaused {
    if (token == address(this)) {
      revert Errors.CannotWithdrawGptTokens();
    }
    if (to == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    ERC20Upgradeable(token).transfer(to, amount);
  }
}
