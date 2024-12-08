// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IGoldPackToken
 * @dev Interface for the Gold Pack Token contract.
 * This interface defines the standard functions and events that a Gold Pack Token contract must implement.
 */
interface IGoldPackToken {
  /// @notice Mint event
  event Mint(address indexed to, uint256 amount);

  /// @notice Admin role granted event
  event AdminRoleGranted(address indexed account);
  /// @notice Admin role revoked event
  event AdminRoleRevoked(address indexed account);
  /// @notice Sales role granted event
  event SalesRoleGranted(address indexed account);
  /// @notice Sales role revoked event
  event SalesRoleRevoked(address indexed account);

  /// @notice Mint function
  function mint(address to, uint256 amount) external;
}
