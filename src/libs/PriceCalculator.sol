// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

library PriceCalculator {
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    /**
     * @dev Calculates the required payment token amount for purchasing GPT tokens.
     * @param goldPrice The current price of gold per troy ounce (8 decimals).
     * @param tokenPrice The current price of the payment token in USD (8 decimals).
     * @param gptAmount The amount of GPT tokens to purchase.
     * @param tokenDecimals The number of decimals the payment token uses.
     * @param tokensPerTroyOunce The number of GPT tokens that represent one troy ounce of gold.
     * @return The required amount of payment tokens.
     */
    function calculateTokenAmount(
        int256 goldPrice,
        int256 tokenPrice,
        uint256 gptAmount,
        uint8 tokenDecimals,
        uint256 tokensPerTroyOunce
    ) internal pure returns (uint256) {
        require(goldPrice > 0, "Invalid gold price");
        require(tokenPrice > 0, "Invalid token price");
        require(tokensPerTroyOunce > 0, "Tokens per troy ounce must be greater than zero");
        require(gptAmount > 0, "GPT amount must be greater than zero");

        // 1. Convert to troy ounces using fixed-point arithmetic with 18 decimals precision
        uint256 troyOunces = (gptAmount * 1e18) / tokensPerTroyOunce;

        // 2. Calculate USD value using fixed-point arithmetic with 18 decimals precision
        uint256 usdNeeded = (uint256(goldPrice) * troyOunces) / 1e18;

        // 3. Convert to payment token amount, rounding up to cover full cost
        uint256 tokenAmount = (usdNeeded * (10 ** tokenDecimals) + uint256(tokenPrice) - 1) / uint256(tokenPrice);

        return tokenAmount;
    }

    /**
     * @dev Gets latest prices from feeds
     */
    function getLatestPrices(AggregatorV3Interface goldFeed, AggregatorV3Interface tokenFeed)
        internal
        view
        returns (int256 goldPrice, int256 tokenPrice)
    {
        // Fetch gold price (XAU/USD)
        uint256 updatedAt;
        (, goldPrice,, updatedAt,) = goldFeed.latestRoundData();
        require(goldPrice > 0, "Invalid gold price from feed");
        require(updatedAt >= block.timestamp - MAX_PRICE_AGE, "Gold price data is stale");

        // Fetch payment token price (e.g., USDC/USD)
        (, tokenPrice,,,) = tokenFeed.latestRoundData();
        require(tokenPrice > 0, "Invalid token price from feed");
    }
}
