// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';

/**
 * @title IBurnVault
 * @notice Interface for the BurnVault contract that handles token burning functionality
 * @dev This interface defines the standard functions and events that a BurnVault contract must implement
 *
 * Key features:
 * - Token deposit and burning functionality
 * - Configurable accepted tokens list
 * - Balance tracking per user
 * - Admin controls for pausing
 * - Access control for privileged operations
 *
 * The BurnVault contract allows users to:
 * - Deposit tokens that can later be burned
 * - Burn tokens after a delay period
 * - Check balances and token acceptance status
 *
 * Admins can:
 * - Update the list of accepted tokens
 * - Burn tokens on behalf of users
 * - Pause/unpause contract functionality
 */
interface IBurnVault {
  /// @notice Updates the accepted tokens list
  function updateAcceptedTokens(ERC20BurnableUpgradeable _token) external;
  /// @notice Removes a token from the accepted tokens list
  function removeAcceptedToken(ERC20BurnableUpgradeable _token) external;
  /// @notice Deposits tokens into the vault
  function depositTokens(uint256 _amount, ERC20BurnableUpgradeable _token) external;
  /// @notice Burns tokens from an account
  function burnTokens(address _account, uint256 _amount, ERC20BurnableUpgradeable _token) external;
  /// @notice Burns all tokens from an account
  function burnAllTokens(address _account, ERC20BurnableUpgradeable _token) external;
  /// @notice Gets the balance of an account
  function getBalance(address account) external view returns (uint256);
  /// @notice Checks if a token is accepted
  function isAcceptedToken(address _token) external view returns (bool);
  /// @notice Pauses the contract
  function pause() external;
  /// @notice Unpauses the contract
  function unpause() external;

  // Events
  /// @notice Tokens deposited event
  event TokensDeposited(address indexed from, uint256 amount);
  /// @notice Tokens burned event
  event TokensBurned(address indexed account, uint256 amount);
  /// @notice Accepted token added event
  event AcceptedTokenAdded(address indexed token);
}
