// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';

/**
 * @title IBurnVault
 * @dev Interface for the Burn Vault contract.
 * This interface defines the standard functions and events that a Burn Vault contract must implement.
 */
interface IBurnVault {
  function updateAcceptedTokens(ERC20BurnableUpgradeable _token) external;
  function removeAcceptedToken(ERC20BurnableUpgradeable _token) external;
  function depositTokens(uint256 _amount, ERC20BurnableUpgradeable _token) external;
  function burnTokens(address _account, uint256 _amount, ERC20BurnableUpgradeable _token) external;
  function burnAllTokens(address _account, ERC20BurnableUpgradeable _token) external;
  function getBalance(address account) external view returns (uint256);
  function isAcceptedToken(address _token) external view returns (bool);
  function pause() external;
  function unpause() external;

  // Events
  event TokensDeposited(address indexed from, uint256 amount);
  event TokensBurned(address indexed account, uint256 amount);
  event AcceptedTokenAdded(address indexed token);
}
