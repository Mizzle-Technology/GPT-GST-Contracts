// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Trading Vault Interface
/**
 * @title ITradingVault
 * @notice Interface for the TradingVault contract that handles token withdrawals with delay and threshold controls
 * @dev This interface defines the standard functions and events that a TradingVault contract must implement
 *
 * Key features:
 * - Queued withdrawal system with delay period
 * - Immediate withdrawals under threshold
 * - Withdrawal request tracking
 * - Admin controls for pausing
 * - Access control for privileged operations
 *
 * The TradingVault contract allows:
 * - Queuing withdrawals that require delay period
 * - Executing queued withdrawals after delay
 * - Immediate withdrawals under threshold
 * - Cancelling pending withdrawals
 * - Configuring withdrawal parameters
 *
 * Admins can:
 * - Set withdrawal wallet address
 * - Update withdrawal threshold
 * - Pause/unpause contract functionality
 * - Execute/cancel withdrawal requests
 */
interface ITradingVault {
  /// @notice Queues a withdrawal request
  function queueWithdrawal(address token, uint256 amount) external returns (bytes32);
  /// @notice Executes a withdrawal request
  function executeWithdrawal(bytes32 requestId) external;
  /// @notice Cancels a withdrawal request
  function cancelWithdrawal(bytes32 requestId) external;
  /// @notice Withdraws tokens immediately
  function withdraw(address token, uint256 amount) external;
  /// @notice Sets the withdrawal wallet address
  function setWithdrawalWallet(address _safeWallet) external returns (bool);
  /// @notice Sets the withdrawal threshold
  function setWithdrawalThreshold(uint256 _threshold) external returns (bool);
  /// @notice Pauses the contract
  function pause() external;
  /// @notice Unpauses the contract
  function unpause() external;

  /// @notice Event emitted when a withdrawal request is queued
  event WithdrawalQueued(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 requestTime,
    uint256 expiry
  );
  /// @notice Event emitted when a withdrawal request is executed
  event WithdrawalExecuted(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 executedTime
  );
  /// @notice Event emitted when a withdrawal request is cancelled
  event WithdrawalCancelled(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 cancelTime
  );
  /// @notice Event emitted when a withdrawal wallet is updated
  event WithdrawalWalletUpdated(address indexed newWallet);
  /// @notice Event emitted when a withdrawal threshold is updated
  event WithdrawalThresholdUpdated(uint256 indexed newThreshold);
  /// @notice Event emitted for immediate withdrawals under threshold
  event ImmediateWithdrawal(address indexed token, uint256 amount, address to, uint256 timestamp);
}
