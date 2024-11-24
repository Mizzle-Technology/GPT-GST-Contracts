// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Errors {
  // Generic errors
  error InsufficientBalance(uint256 balance, uint256 amount);
  error AddressCannotBeZero();
  error InvalidAmount(uint256 amount);
  error DuplicatedToken(address token);

  // AccessControl errors
  error DefaultAdminRoleNotGranted(address account);
  error AdminRoleNotGranted(address account);
  error SalesRoleNotGranted(address account);

  // BurnVault errors
  error TooEarlyToBurn();

  // TradingVault errors
  error DuplicatedWithdrawalRequest(bytes32 requestId);
  error WithdrawalRequestNotFound(bytes32 requestId);
  error WithdrawalAlreadyExecuted(bytes32 requestId);
  error WithdrawalAlreadyCancelled(bytes32 requestId);
  error WithdrawalDelayNotMet(bytes32 requestId);
  error WithdrawalThresholdNotMet(uint256 amount, uint256 threshold);
  error SafeWalletNotSet();
}
