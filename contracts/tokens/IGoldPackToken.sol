// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IGoldPackToken
 * @dev Interface for the Gold Pack Token contract.
 * This interface defines the standard functions and events that a Gold Pack Token contract must implement.
 */
interface IGoldPackToken {
  // Events for token minting and burning
  event Mint(address indexed to, uint256 amount);
  event BurnVaultSet(address indexed burnVault);

  // Events for role management
  event AdminRoleGranted(address indexed account);
  event AdminRoleRevoked(address indexed account);
  event SalesRoleGranted(address indexed account);
  event SalesRoleRevoked(address indexed account);

  // Functions declarations
  function mint(address to, uint256 amount) external;
  function depositToBurnVault(uint256 amount) external;
  function RedeemAllCoins(address account) external;
  function RedeemCoins(address _account, uint256 _amount) external;
  function getBurnVaultAddress() external view returns (address);
}
