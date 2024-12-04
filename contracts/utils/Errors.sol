// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Errors
 * @notice This library contains error codes and messages for various conditions in the contracts.
 */
library Errors {
  // Generic errors
  error InsufficientBalance(uint256 balance, uint256 amount);
  error AddressCannotBeZero();
  error InvalidAmount(uint256 amount);
  error DuplicatedToken(address token);
  error InsufficientAllowance(uint256 allowance, uint256 amount);
  error MaxSizeExceeded();
  error EmptyList();
  error InvalidTokenPrice();
  error TokenPriceStale();
  error AmountCannotBeZero();

  // AccessControl errors
  error DefaultAdminRoleNotGranted(address account);
  error AdminRoleNotGranted(address account);
  error SalesRoleNotGranted(address account);
  error AdminRoleAlreadyGranted(address account);
  error SalesRoleAlreadyGranted(address account);

  // GoldPackToken errors
  error CannotWithdrawGptTokens();

  // BurnVault errors
  error TooEarlyToBurn();
  error InvalidTroyOunceAmount(uint256 amount);
  error NoTokensToBurn();

  // TradingVault errors
  error DuplicatedWithdrawalRequest(bytes32 requestId);
  error WithdrawalRequestNotFound(bytes32 requestId);
  error WithdrawalAlreadyExecuted(bytes32 requestId);
  error WithdrawalAlreadyCancelled(bytes32 requestId);
  error WithdrawalDelayNotMet(bytes32 requestId);
  error WithdrawalThresholdNotMet(uint256 amount, uint256 threshold);
  error SafeWalletNotSet();
  error AmountExceedsThreshold(uint256 amount, uint256 threshold);

  // SalesContract errors
  error InvalidUserSignature(bytes signature);
  error InvalidRelayerSignature(bytes signature);
  error InvalidNonce(uint256 nonce);
  error RoundNotExist();
  error RoundAlreadyActive();
  error RoundNotActive();
  error RoundAlreadyEnded();
  error RoundNotStarted();
  error RoundStageInvalid();
  error NotWhitelisted();
  error BuyerMismatch();
  error TokenNotAccepted(address token);
  error TokenAlreadyAccepted(address token);
  error SignatureExpired();
  error OrderAlreadyExpired();
  error InvalidTimeRange(uint256 startTime, uint256 endTime);
  error ExceedMaxAllocation(uint256 amount, uint256 maxTokens);
  error CannotRecoverGptToken();
  error AddressNotWhitelisted(address addr);
  error BurnVaultAlreadySet(address burnVault);

  // RewardDistribution errors
  error SharesMustBeGreaterThanZero();
  error TotalSharesExceedMaximum();
  error ShareholderAlreadyExists(address account);
  error ShareholderNotFound(address account);
  error RewardsAlreadyLocked(address account);
  error RewardsNotLocked(address account);
  error ShareholderNotActivated(address account);
  error ShareholderLocked(address account);
  error NoSharesAssigned(address account);
  error RewardsAlreadyClaimed(address account);
  error RewardsNotYetClaimable(bytes32 distributionId);
}
