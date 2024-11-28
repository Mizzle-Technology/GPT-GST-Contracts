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

library SalesLib {
  using SafeERC20 for ERC20Upgradeable;
  using CalculationLib for *;

  // === Signature Verification ===
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
    require(!tradingVault.paused(), 'Vault is paused');
    require(round.isActive, 'No active round');
    require(block.timestamp <= round.endTime, 'Round ended');
    require(round.tokensSold + amount <= round.maxTokens, 'Exceeds round limit');
    require(tokenConfig.isAccepted, 'Token not accepted');

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
    require(allowance >= tokenAmount, 'Token allowance too low');

    ERC20Upgradeable(paymentToken).safeTransferFrom(buyer, address(tradingVault), tokenAmount);
    round.tokensSold += amount;
    gptToken.mint(buyer, amount);
  }
}
