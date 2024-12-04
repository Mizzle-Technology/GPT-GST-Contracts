// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Trading Vault Interface
interface ITradingVault {
  function queueWithdrawal(address token, uint256 amount) external returns (bytes32);
  function executeWithdrawal(bytes32 requestId) external;
  function cancelWithdrawal(bytes32 requestId) external;
  function withdraw(address token, uint256 amount) external;
  function setWithdrawalWallet(address _safeWallet) external returns (bool);
  function setWithdrawalThreshold(uint256 _threshold) external returns (bool);
  function pause() external;
  function unpause() external;

  event WithdrawalQueued(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 requestTime,
    uint256 expiry
  );
  event WithdrawalExecuted(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 executedTime
  );
  event WithdrawalCancelled(
    bytes32 indexed requestId,
    address token,
    uint256 amount,
    address to,
    uint256 cancelTime
  );
  event WithdrawalWalletUpdated(address indexed newWallet);
  event WithdrawalThresholdUpdated(uint256 indexed newThreshold);
  event ImmediateWithdrawal(address indexed token, uint256 amount, address to, uint256 timestamp);
}
