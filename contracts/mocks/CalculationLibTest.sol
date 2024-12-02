// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../../contracts/libs/CalculationLib.sol';

contract CalculationLibTest {
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

  function getLatestPrice(AggregatorV3Interface priceFeed) external view returns (int256, uint256) {
    return CalculationLib.getLatestPrice(priceFeed);
  }
}
