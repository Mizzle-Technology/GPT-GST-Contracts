// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Errors
 * @notice Library containing custom error definitions used across contracts
 * @dev This library centralizes error handling by defining revert messages as custom errors
 *
 * Error categories:
 * - Generic errors: Basic validation and state errors
 * - AccessControl errors: Role and permission related errors
 * - GoldPackToken errors: Errors specific to GPT token operations
 * - BurnVault errors: Errors related to token burning functionality
 * - TradingVault errors: Errors for withdrawal and trading operations
 * - SalesContract errors: Errors related to token sales and rounds
 */
library Errors {
  // Generic errors
  /// @notice Insufficient balance error
  error InsufficientBalance(uint256 balance, uint256 amount);
  /// @notice Address cannot be zero error
  error AddressCannotBeZero();
  /// @notice Invalid amount error
  error InvalidAmount(uint256 amount);
  /// @notice Duplicated token error
  error DuplicatedToken(address token);
  /// @notice Insufficient allowance error
  error InsufficientAllowance(uint256 allowance, uint256 amount);
  /// @notice Max size exceeded error
  error MaxSizeExceeded();
  /// @notice Empty list error
  error EmptyList();
  /// @notice Invalid token price error
  error InvalidTokenPrice();
  /// @notice Token price stale error
  error TokenPriceStale();
  /// @notice Amount cannot be zero error
  error AmountCannotBeZero();

  // AccessControl errors
  /// @notice Default admin role not granted error
  error DefaultAdminRoleNotGranted(address account);
  /// @notice Admin role not granted error
  error AdminRoleNotGranted(address account);
  /// @notice Sales role not granted error
  error SalesRoleNotGranted(address account);
  /// @notice Admin role already granted error
  error AdminRoleAlreadyGranted(address account);
  /// @notice Sales role already granted error
  error SalesRoleAlreadyGranted(address account);

  // GoldPackToken errors
  /// @notice Cannot withdraw GPT tokens error
  error CannotWithdrawGptTokens();

  // BurnVault errors
  /// @notice Too early to burn error
  error TooEarlyToBurn();
  /// @notice Invalid Troy ounce amount error
  error InvalidTroyOunceAmount(uint256 amount);
  /// @notice No tokens to burn error
  error NoTokensToBurn();

  // TradingVault errors
  /// @notice Duplicated withdrawal request error
  error DuplicatedWithdrawalRequest(bytes32 requestId);
  /// @notice Withdrawal request not found error
  error WithdrawalRequestNotFound(bytes32 requestId);
  /// @notice Withdrawal already executed error
  error WithdrawalAlreadyExecuted(bytes32 requestId);
  /// @notice Withdrawal already cancelled error
  error WithdrawalAlreadyCancelled(bytes32 requestId);
  /// @notice Withdrawal delay not met error
  error WithdrawalDelayNotMet(bytes32 requestId);
  /// @notice Safe wallet not set error
  error SafeWalletNotSet();
  /// @notice Amount exceeds threshold error
  error AmountExceedsThreshold(uint256 amount, uint256 threshold);
  /// @notice Vault paused error
  error VaultPaused();
  /// @notice No active round error
  error NoActiveRound();
  /// @notice Round ended error
  error RoundEnded();
  /// @notice Exceeds round limit error
  error ExceedsRoundLimit();
  /// @notice Same threshold error
  error SameThreshold();
  /// @notice Same wallet address error
  error SameWalletAddress();

  // SalesContract errors
  /// @notice Invalid user signature error
  error InvalidUserSignature(bytes signature);
  /// @notice Invalid relayer signature error
  error InvalidRelayerSignature(bytes signature);
  /// @notice Invalid nonce error
  error InvalidNonce(uint256 nonce);
  /// @notice Round does not exist error
  error RoundNotExist();
  /// @notice Round already active error
  error RoundAlreadyActive();
  /// @notice Round not active error
  error RoundNotActive();
  /// @notice Round already ended error
  error RoundAlreadyEnded();
  /// @notice Round not started error
  error RoundNotStarted();
  /// @notice Round stage invalid error
  error RoundStageInvalid();
  /// @notice Not whitelisted error
  error NotWhitelisted();
  /// @notice Buyer mismatch error
  error BuyerMismatch();
  /// @notice Token not accepted error
  error TokenNotAccepted(address token);
  /// @notice Token already accepted error
  error TokenAlreadyAccepted(address token);
  /// @notice Order already expired error
  error OrderAlreadyExpired();
  /// @notice Invalid time range error
  error InvalidTimeRange(uint256 startTime, uint256 endTime);
  /// @notice Exceed max allocation error
  error ExceedMaxAllocation(uint256 amount, uint256 maxTokens);
  /// @notice Cannot recover GPT token error
  error CannotRecoverGptToken();
  /// @notice Address not whitelisted error
  error AddressNotWhitelisted(address addr);
  /// @notice Invalid gold price error
  error InvalidGoldPrice();

  // RewardDistribution errors
  /// @notice Total shares exceed maximum error
  error TotalSharesExceedMaximum();
  /// @notice Shareholder already exists error
  error ShareholderAlreadyExists(address account);
  /// @notice Shareholder not found error
  error ShareholderNotFound(address account);
  /// @notice Rewards already locked error
  error RewardsAlreadyLocked(address account);
  /// @notice Rewards not locked error
  error RewardsNotLocked(address account);
  /// @notice Shareholder not activated error
  error ShareholderNotActivated(address account);
  /// @notice Shareholder locked error
  error ShareholderLocked(address account);
  /// @notice No shares assigned error
  error NoSharesAssigned(address account);
  /// @notice Rewards already claimed error
  error RewardsAlreadyClaimed(address account);
  /// @notice Rewards not yet claimable error
  error RewardsNotYetClaimable(bytes32 distributionId);
  /// @notice Distribution finalized error
  error DistributionFinalized(bytes32 distributionId);
  /// @notice Not all rewards claimed error
  error NotAllRewardsClaimed(bytes32 distributionId);

  // LinkedMap errors
  /// @notice Key already exists error
  error KeyAlreadyExists(bytes32 key);
  /// @notice Key does not exist error
  error KeyDoesNotExist(bytes32 key);
}
