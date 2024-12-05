// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './ITradingVault.sol';
import {Errors} from '../utils/Errors.sol';
/**
 * @title TradingVault
 * @notice Contract for managing token withdrawals with delay and threshold controls
 * @dev Implementation details:
 * - Allows queuing withdrawals with a delay period
 * - Enforces withdrawal thresholds requiring admin approval
 * - Supports immediate withdrawals under threshold
 * - Includes access control for admin functions
 * - Upgradeable via UUPS proxy pattern
 * - Pausable for emergency situations
 *
 * Key features:
 * - Withdrawal request tracking
 * - Configurable withdrawal threshold
 * - Safe wallet integration
 * - Admin role for privileged operations
 * - Withdrawal delay enforcement
 * - Emergency pause functionality
 * - Access control for role management
 * - UUPS upgradeable pattern
 */

contract TradingVault is
  Initializable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  ITradingVault
{
  using SafeERC20 for ERC20Upgradeable;

  /// @notice Admin role
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  /// @notice Withdrawal delay
  uint256 public constant WITHDRAWAL_DELAY = 1 days;

  /// @notice Storage gap
  uint256[50] private __gap;

  /// @notice Withdrawal request struct
  struct WithdrawalRequest {
    address token;
    uint256 amount;
    address transfer_to;
    uint256 expiry;
    uint256 requestTime;
    bool executed;
    bool cancelled;
  }

  /// @notice Withdrawal wallet
  address public safeWallet;
  /// @notice Withdrawal threshold
  uint256 public WITHDRAWAL_THRESHOLD; // 100k USDC
  /// @notice Withdrawal requests mapping
  mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;

  /**
   * @notice Initializes the TradingVault contract
   * @param _safeWallet Address of the safe wallet for withdrawals
   * @param _admin Address of the admin
   * @param _super Address of the super admin
   */
  function initialize(address _safeWallet, address _admin, address _super) public initializer {
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    require(_safeWallet != address(0), 'Invalid wallet address');
    safeWallet = _safeWallet;
    WITHDRAWAL_THRESHOLD = 100000 * 10 ** 6; // 100k USDC
  }

  // === modifier ===
  /**
   * @notice Modifier to check if the caller has the DEFAULT_ADMIN_ROLE
   * @dev Reverts if the caller does not have the DEFAULT_ADMIN_ROLE
   */
  modifier onlyDefaultAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @notice Modifier to check if the caller has the ADMIN_ROLE
   * @dev Reverts if the caller does not have the ADMIN_ROLE
   */
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  // === Queued Withdrawal Functions ===
  /**
   * @notice Queues a withdrawal request for a specified token and amount.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   *      It requires the contract to be not paused and is protected against reentrancy.
   * @param token The address of the token to withdraw.
   * @param amount The amount of the token to withdraw.
   * require The amount must be greater than 0.
   * require The token address must be valid (non-zero address).
   * emit WithdrawalQueued Emitted when a withdrawal request is successfully queued.
   */
  function queueWithdrawal(
    address token,
    uint256 amount
  ) external override onlyAdmin whenNotPaused nonReentrant returns (bytes32) {
    bytes32 requestId = keccak256(abi.encodePacked(token, amount, block.timestamp));

    if (withdrawalRequests[requestId].amount > 0) {
      revert Errors.DuplicatedWithdrawalRequest(requestId);
    }

    if (amount <= 0) {
      revert Errors.InvalidAmount(amount);
    }

    if (token == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    if (IERC20(token).balanceOf(address(this)) < amount) {
      revert Errors.InsufficientBalance(IERC20(token).balanceOf(address(this)), amount);
    }

    withdrawalRequests[requestId] = WithdrawalRequest({
      amount: amount,
      token: token,
      transfer_to: safeWallet,
      requestTime: block.timestamp,
      expiry: block.timestamp + WITHDRAWAL_DELAY,
      executed: false,
      cancelled: false
    });

    emit WithdrawalQueued(
      requestId,
      token,
      amount,
      safeWallet,
      block.timestamp,
      block.timestamp + WITHDRAWAL_DELAY
    );

    return requestId;
  }

  /**
   * @notice Executes a withdrawal request after verifying all conditions.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function checks if the request ID is valid, the request has not been executed or cancelled,
   * and the required withdrawal delay has passed before marking the request as executed and transferring the tokens.
   * @param requestId The ID of the withdrawal request to be executed.
   * require requestId must be less than the length of withdrawalRequests array.
   * require The request must not have been executed already.
   * require The request must not have been cancelled.
   * require The current block timestamp must be greater than or equal to the request time plus the withdrawal delay.
   * emit WithdrawalExecuted Emitted when a withdrawal request is successfully executed.
   */
  function executeWithdrawal(bytes32 requestId) external onlyAdmin whenNotPaused nonReentrant {
    WithdrawalRequest storage request = withdrawalRequests[requestId];
    // if request id does not exist, it will revert
    if (request.amount == 0) {
      revert Errors.WithdrawalRequestNotFound(requestId);
    }

    if (request.executed) {
      revert Errors.WithdrawalAlreadyExecuted(requestId);
    }

    if (request.cancelled) {
      revert Errors.WithdrawalAlreadyCancelled(requestId);
    }

    uint256 contractBalance = ERC20Upgradeable(request.token).balanceOf(address(this));
    if (contractBalance <= request.amount) {
      revert Errors.InsufficientBalance(contractBalance, request.amount);
    }

    if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY) {
      revert Errors.WithdrawalDelayNotMet(requestId);
    }

    ERC20Upgradeable(request.token).safeTransfer(request.transfer_to, request.amount);
    request.executed = true;

    emit WithdrawalExecuted(
      requestId,
      request.token,
      request.amount,
      request.transfer_to,
      block.timestamp
    );
  }

  /**
   * @notice Cancels a withdrawal request.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function checks if the request ID is valid, the request has not been executed or cancelled,
   * and the request has not expired before marking the request as cancelled.
   * @param requestId The ID of the withdrawal request to be cancelled.
   * require requestId must be less than the length of withdrawalRequests array.
   * require The request must not have been executed already.
   * require The request must not have been cancelled already.
   * require The current block timestamp must be less than the request expiry time.
   * emit WithdrawalCancelled Emitted when a withdrawal request is successfully cancelled.
   */
  function cancelWithdrawal(bytes32 requestId) external onlyAdmin whenNotPaused nonReentrant {
    WithdrawalRequest storage request = withdrawalRequests[requestId];
    if (request.amount == 0) {
      revert Errors.WithdrawalRequestNotFound(requestId);
    }

    if (request.executed) {
      revert Errors.WithdrawalAlreadyExecuted(requestId);
    }

    if (request.cancelled) {
      revert Errors.WithdrawalAlreadyCancelled(requestId);
    }

    if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY) {
      revert Errors.WithdrawalDelayNotMet(requestId);
    }

    request.cancelled = true;

    emit WithdrawalCancelled(
      requestId,
      request.token,
      request.amount,
      request.transfer_to,
      block.timestamp
    );
  }

  /**
   * @notice Withdraws tokens immediately to the withdrawal wallet.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function transfers the specified amount of tokens to the withdrawal wallet.
   * @param token The address of the token to withdraw.
   * @param amount The amount of the token to withdraw.
   * require The amount must be greater than 0.
   * emit ImmediateWithdrawal Emitted when a withdrawal request is successfully executed.
   */
  function withdraw(address token, uint256 amount) external onlyAdmin whenNotPaused nonReentrant {
    if (amount > WITHDRAWAL_THRESHOLD) {
      revert Errors.AmountExceedsThreshold(amount, WITHDRAWAL_THRESHOLD);
    }

    if (amount <= 0) {
      revert Errors.InvalidAmount(amount);
    }

    if (token == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    uint256 contractBalance = ERC20Upgradeable(token).balanceOf(address(this));
    if (contractBalance <= amount) {
      revert Errors.InsufficientBalance(contractBalance, amount);
    }

    if (safeWallet == address(0)) {
      revert Errors.SafeWalletNotSet();
    }

    ERC20Upgradeable(token).safeTransfer(safeWallet, amount);

    emit ImmediateWithdrawal(token, amount, safeWallet, block.timestamp);
  }

  // === Admin functions ===
  /**
   * @notice Sets the withdrawal wallet address for the trading vault.
   * @dev This function allows the owner to update the wallet address where funds will be withdrawn.
   * @param _safeWallet The address of the new withdrawal wallet.
   * @return success A boolean value indicating whether the wallet address was successfully updated.
   */
  function setWithdrawalWallet(address _safeWallet) external onlyDefaultAdmin returns (bool) {
    require(_safeWallet != address(0), 'Invalid wallet address');
    require(safeWallet != _safeWallet, 'Same wallet address');
    safeWallet = _safeWallet;
    emit WithdrawalWalletUpdated(_safeWallet);
    return true;
  }

  /**
   * @notice Sets the withdrawal threshold for immediate withdrawals.
   * @dev This function allows the owner to update the threshold amount for immediate withdrawals.
   * @param _threshold The new threshold amount for immediate withdrawals.
   * @return success A boolean value indicating whether the threshold was successfully updated.
   */
  function setWithdrawalThreshold(uint256 _threshold) external onlyDefaultAdmin returns (bool) {
    require(_threshold > 0, 'Threshold must be greater than 0');
    require(WITHDRAWAL_THRESHOLD != _threshold, 'Same threshold');

    WITHDRAWAL_THRESHOLD = _threshold;

    emit WithdrawalThresholdUpdated(_threshold);
    return true;
  }

  // == Pausable functions ==
  /**
   * @notice Pauses the contract.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   */
  function pause() external onlyAdmin {
    _pause();
  }

  /**
   * @notice Unpauses the contract.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   */
  function unpause() external onlyAdmin {
    _unpause();
  }

  // === UUPS Upgrade ===
  /**
   * @notice Authorizes the upgrade of the contract to a new implementation.
   * @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE.
   * @param newImplementation The address of the new implementation.
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyDefaultAdmin {}

  // === View Functions ===
  /**
   * @notice Gets the balance of the contract for a given token.
   * @param _token The address of the token to check.
   * @return The balance of the contract for the given token.
   */
  function getBalance(address _token) external view returns (uint256) {
    if (_token == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    return ERC20Upgradeable(_token).balanceOf(address(this));
  }
}
