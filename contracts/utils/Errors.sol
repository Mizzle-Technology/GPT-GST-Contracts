// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Errors {
  // Generic errors
  error InsufficientBalance(uint256 balance, uint256 amount);
  error AddressCannotBeZero();
  error InvalidAmount(uint256 amount);
  error DuplicatedToken(address token);
  error InsufficientAllowance(uint256 allowance, uint256 amount);
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
}
