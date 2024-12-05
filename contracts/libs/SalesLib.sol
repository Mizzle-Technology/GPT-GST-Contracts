// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';
import '../vaults/TradingVault.sol';
import '../tokens/GoldPackToken.sol';
import './CalculationLib.sol';
import '../sales/ISalesContract.sol';

/**
 * @title SalesLib
 * @dev Library for handling token sales functionality.
 * @notice This library provides functions to process token purchases and verify signatures.
 *
 * @dev Key Features:
 * - Verifies signatures for user orders
 * - Processes token purchases with price calculations
 * - Handles payment token transfers and GPT token minting
 * - Validates purchase requirements and limits
 *
 * @dev Purchase Flow:
 * 1. Verify signature if required
 * 2. Check round and vault status
 * 3. Calculate payment amount based on current prices
 * 4. Validate user balance
 * 5. Process payment and mint tokens
 *
 * @dev Important Validations:
 * - Active round check
 * - Round limits check
 * - Payment token acceptance check
 * - User balance check
 * - Price staleness check
 *
 * @dev Usage:
 * ```solidity
 * bool isValid = SalesLib.verifySignature(
 *   domainSeparator,
 *   orderHash,
 *   buyer,
 *   signature
 * );
 *
 * uint256 paymentAmount = SalesLib.processPurchase(
 *   goldPriceFeed,
 *   tokenConfig,
 *   tradingVault,
 *   gptToken,
 *   round,
 *   amount,
 *   paymentToken,
 *   buyer,
 *   tokensPerTroyOunce
 * );
 * ```
 */
library SalesLib {
  using SafeERC20 for ERC20Upgradeable;
  using CalculationLib for *;

  // === Signature Verification ===
  /**
   * @notice Verifies a signature for a user order.
   * @param domainSeparator The domain separator for the order.
   * @param userOrderHash The hash of the user order.
   * @param buyer The address of the buyer.
   * @param signature The signature to verify.
   * @return isValid True if the signature is valid, false otherwise.
   */
  function verifySignature(
    bytes32 domainSeparator,
    bytes32 userOrderHash,
    address buyer,
    bytes memory signature
  ) internal view returns (bool) {
    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, userOrderHash));
    return SignatureChecker.isValidSignatureNow(buyer, digest, signature);
  }

  // === Purchase Processing ===
  /**
   * @notice Processes a purchase of GPT tokens.
   * @param goldPriceFeed The Chainlink price feed for gold.
   * @param tokenConfig The configuration for the token being purchased.
   * @param tradingVault The trading vault for handling token transfers.
   * @param gptToken The GPT token contract for minting new tokens.
   * @param round The current round of sales.
   * @param amount The amount of tokens to purchase.
   * @param paymentToken The payment token address.
   * @param buyer The address of the buyer.
   * @param tokensPerTroyOunce The number of tokens per troy ounce.
   * @return tokenAmount The amount of payment tokens transferred.
   */
  function processPurchase(
    AggregatorV3Interface goldPriceFeed,
    ISalesContract.TokenConfig memory tokenConfig,
    TradingVault tradingVault,
    GoldPackToken gptToken,
    ISalesContract.Round storage round,
    uint256 amount,
    address paymentToken,
    address buyer,
    uint256 tokensPerTroyOunce
  ) internal returns (uint256 tokenAmount) {
    if (tradingVault.paused()) revert Errors.VaultPaused();
    if (!round.isActive) revert Errors.NoActiveRound();
    if (block.timestamp > round.endTime) revert Errors.RoundEnded();
    if (round.tokensSold + amount > round.maxTokens) revert Errors.ExceedsRoundLimit();
    if (!tokenConfig.isAccepted) revert Errors.TokenNotAccepted(paymentToken);

    (int256 goldPrice, ) = CalculationLib.getLatestPrice(goldPriceFeed);
    (int256 tokenPrice, ) = CalculationLib.getLatestPrice(tokenConfig.priceFeed);

    tokenAmount = CalculationLib.calculatePaymentTokenAmount(
      goldPrice,
      tokenPrice,
      amount,
      tokenConfig.decimals,
      tokensPerTroyOunce
    );

    uint256 userBalance = ERC20Upgradeable(paymentToken).balanceOf(buyer);

    if (userBalance < tokenAmount) {
      revert Errors.InsufficientBalance(userBalance, tokenAmount);
    }

    // Transfer tokens to the vault
    uint256 allowance = ERC20Upgradeable(paymentToken).allowance(buyer, address(this));
    if (allowance < tokenAmount) revert Errors.InsufficientAllowance(allowance, tokenAmount);

    ERC20Upgradeable(paymentToken).safeTransferFrom(buyer, address(tradingVault), tokenAmount);
    round.tokensSold += amount;
    gptToken.mint(buyer, amount);
  }
}
