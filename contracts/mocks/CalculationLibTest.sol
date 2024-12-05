// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../../contracts/libs/CalculationLib.sol';

/**
 * @title CalculationLibTest
 * @notice Test contract for CalculationLib functions
 * @dev Exposes CalculationLib functions for testing purposes
 *
 * This contract provides external functions to test:
 * - calculatePaymentTokenAmount: Calculates payment token amount from GPT amount
 * - calculateGptAmount: Calculates GPT amount from payment token amount
 * - getLatestPrice: Gets latest price from Chainlink price feed
 *
 * The contract is used for testing the core calculation functions used in
 * token conversions and price lookups.
 */

contract CalculationLibTest {
  /// @notice Calculates payment token amount from GPT amount
  function calculatePaymentTokenAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 gptAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) external pure returns (uint256) {
    return
      CalculationLib.calculatePaymentTokenAmount(
        goldPrice,
        tokenPrice,
        gptAmount,
        tokenDecimals,
        tokensPerTroyOunce
      );
  }

  /// @notice Calculates GPT amount from payment token amount
  function calculateGptAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 paymentTokenAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) external pure returns (uint256) {
    return
      CalculationLib.calculateGptAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenDecimals,
        tokensPerTroyOunce
      );
  }

  /// @notice Gets latest price from Chainlink price feed
  function getLatestPrice(AggregatorV3Interface priceFeed) external view returns (int256, uint256) {
    return CalculationLib.getLatestPrice(priceFeed);
  }
}
