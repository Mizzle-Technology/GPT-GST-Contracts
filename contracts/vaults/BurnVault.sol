// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../interface/IBurnVault.sol';
import {Errors} from '../utils/Errors.sol';

/**
 * @title BurnVault
 * @notice Contract for burning GPT tokens after a delay period
 * @dev Implementation details:
 * - Accepts GPT token deposits from users
 * - Enforces a 7 day delay before burning is allowed
 * - Burns tokens in increments of 10000 GPT (1 Troy ounce)
 * - Includes access control for admin functions
 * - Upgradeable via UUPS proxy pattern
 * - Pausable for emergency situations
 *
 * Key features:
 * - Deposit tracking per user
 * - Configurable accepted tokens
 * - Admin role for privileged operations
 * - Burn delay enforcement
 * - Troy ounce conversion handling
 * - Emergency pause functionality
 * - Access control for role management
 * - UUPS upgradeable pattern
 */
contract BurnVault is
  Initializable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  OwnableUpgradeable,
  IBurnVault
{
  using SafeERC20 for ERC20Upgradeable;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @notice Role for administrative functions
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  /// @notice 1 Troy ounce = 10000 GPT tokens
  uint256 public constant TOKENS_PER_TROY_OUNCE = 10000;
  /// @notice The delay before tokens can be burned after a deposit
  uint256 public constant BURN_DELAY = 7 days;

  /// @notice Storage gap for future upgrades
  uint256[50] private __gap;

  /// @notice Struct to store deposit information
  struct Deposit {
    /// @notice The amount of tokens deposited
    uint256 amount;
    /// @notice The timestamp of the deposit
    uint256 timestamp;
  }

  /// @notice Mapping of deposits by user address
  mapping(address => Deposit) public deposits;

  /// @notice Accepted Tokens
  EnumerableSet.AddressSet private acceptedTokens;

  /**
   * @dev First initialization step - sets up roles
   * @param _super The address of the super admin (owner)
   * @param _admin The address of the admin
   */
  function initialize(address _super, address _admin) public initializer {
    if (_super == address(0) || _admin == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __Ownable_init(_super);

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
  }

  // modifier to check if the caller has the required role

  /**
   * @dev Modifier to check if the caller has the super admin role
   */
  modifier onlySuperAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @dev Modifier to check if the caller has the admin role
   */
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @dev Sets the token address.
   * @param _token The address of the token contract.
   * Requirements:
   * - Caller must have `DEFAULT_ADMIN_ROLE`.
   */
  function updateAcceptedTokens(ERC20BurnableUpgradeable _token) external onlyAdmin {
    if (address(_token) == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    if (acceptedTokens.contains(address(_token))) {
      revert Errors.DuplicatedToken(address(_token));
    }

    acceptedTokens.add(address(_token));

    emit AcceptedTokenAdded(address(_token));
  }

  /**
   * @dev Removes the token from the accepted tokens list.
   * @param _token The address of the token contract.
   * Requirements:
   * - Caller must have `DEFAULT_ADMIN_ROLE`.
   */
  function removeAcceptedToken(ERC20BurnableUpgradeable _token) external onlyAdmin {
    if (address(_token) == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    if (!acceptedTokens.contains(address(_token))) {
      revert Errors.TokenNotAccepted(address(_token));
    }

    acceptedTokens.remove(address(_token));
  }

  /**
   * @dev Deposits `amount` tokens to the vault.
   * @param _amount The amount of tokens to deposit.
   * @param _token The token to deposit.
   * Requirements:
   * - `amount` must be greater than zero.
   * - Caller must have approved the vault to spend `amount` tokens.
   * Emits a {TokensDeposited} event.
   */
  function depositTokens(
    uint256 _amount,
    ERC20BurnableUpgradeable _token
  ) public nonReentrant whenNotPaused {
    if (_amount == 0) {
      revert Errors.AmountCannotBeZero();
    }

    // check the allowance of the token
    uint256 allowance = _token.allowance(msg.sender, address(this));
    if (allowance < _amount) {
      revert Errors.InsufficientAllowance(allowance, _amount);
    }

    // Token must be in the accepted tokens list
    if (!acceptedTokens.contains(address(_token))) {
      revert Errors.TokenNotAccepted(address(_token));
    }

    // Add validation for Troy ounce amounts if needed
    if (_amount % TOKENS_PER_TROY_OUNCE != 0) {
      revert Errors.InvalidTroyOunceAmount(_amount);
    }

    // Transfer tokens to vault
    ERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);

    // Update the deposit record
    deposits[msg.sender] = Deposit({
      amount: deposits[msg.sender].amount + _amount, // Accumulate deposits
      timestamp: block.timestamp
    });

    emit TokensDeposited(msg.sender, _amount);
  }

  /**
   * @dev Burns tokens from the specified account.
   * @param _account The account whose tokens to burn.
   * @param _amount The amount of tokens to burn.
   * @param _token The token to burn.
   * Requirements:
   * - Caller must have `ADMIN_ROLE`.
   * - `BURN_DELAY` must have passed since the last deposit.
   * Emits a {TokensBurned} event.
   */
  function burnTokens(
    address _account,
    uint256 _amount,
    ERC20BurnableUpgradeable _token
  ) public nonReentrant whenNotPaused onlyAdmin {
    _burn(_account, _amount, _token);
  }

  /**
   * @notice Burns all tokens from the specified account.
   * @dev Explain to a developer any extra details
   * @param _account The account whose tokens to burn.
   *  emits a {TokensBurned} event.
   */
  function burnAllTokens(
    address _account,
    ERC20BurnableUpgradeable _token
  ) external nonReentrant whenNotPaused onlyAdmin {
    _burn(_account, deposits[_account].amount, _token);
  }

  /**
   * @dev Internal function to burn tokens from an account.
   * @param _account The account whose tokens to burn.
   * @param _amount The amount of tokens to burn.
   * @param _token The token to burn.
   * Requirements:
   * - Account cannot be zero address
   * - Amount cannot be zero
   * - Account must have sufficient balance
   * - Token must be accepted
   * - Vault must have sufficient balance
   * - BURN_DELAY must have passed since last deposit
   * Emits a {TokensBurned} event.
   */
  function _burn(address _account, uint256 _amount, ERC20BurnableUpgradeable _token) internal {
    if (_account == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    if (_amount == 0) {
      revert Errors.AmountCannotBeZero();
    }

    Deposit storage deposit = deposits[_account];

    if (deposit.amount == 0) {
      revert Errors.NoTokensToBurn();
    }

    if (deposit.amount < _amount) {
      revert Errors.InsufficientBalance(deposit.amount, _amount);
    }

    if (!acceptedTokens.contains(address(_token))) {
      revert Errors.TokenNotAccepted(address(_token));
    }

    if (ERC20Upgradeable(_token).balanceOf(address(this)) < _amount) {
      revert Errors.InsufficientBalance(ERC20Upgradeable(_token).balanceOf(address(this)), _amount);
    }

    if (deposit.amount < _amount) {
      revert Errors.InsufficientBalance(deposit.amount, _amount);
    }

    if (block.timestamp < deposit.timestamp + BURN_DELAY) {
      // Not enough time has passed since the last deposit
      revert Errors.TooEarlyToBurn();
    }

    // Burn tokens held by vault
    _token.burn(_amount);

    // update the deposit record
    deposits[_account].amount -= _amount;

    emit TokensBurned(_account, _amount);
  }

  /**
   * @dev Returns the balance of the specified account.
   * @param account The account whose balance to return.
   * @return The balance of the account.
   */
  function getBalance(address account) external view returns (uint256) {
    return deposits[account].amount;
  }

  // === Pause Functions ===

  /**
   * @dev Pauses the contract.
   * Requirements:
   * - Caller must have `DEFAULT_ADMIN_ROLE`.
   */
  function pause() external onlySuperAdmin {
    _pause();
  }

  /**
   * @dev Unpauses the contract.
   * Requirements:
   * - Caller must have `DEFAULT_ADMIN_ROLE`.
   */
  function unpause() external onlySuperAdmin {
    _unpause();
  }

  // === View Functions ===
  /**
   * @notice Checks if a token is accepted.
   * @param _token The address of the token to check.
   * @return True if the token is accepted, false otherwise.
   */
  function isAcceptedToken(address _token) external view returns (bool) {
    return acceptedTokens.contains(_token);
  }

  // === UUPS Functions ===
  /**
   * @notice Authorizes the upgrade of the contract to a new implementation.
   * @param newImplementation The address of the new implementation.
   *
   * Requirements:
   * - Only the super admin can authorize the upgrade.
   */
  function _authorizeUpgrade(address newImplementation) internal override onlySuperAdmin {}
}
