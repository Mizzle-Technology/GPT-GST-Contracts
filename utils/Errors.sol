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
}
