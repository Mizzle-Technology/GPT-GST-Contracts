// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import "forge-std/console.sol";

library PriceCalculator {
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    /**
     * @dev Calculates the required payment token amount for purchasing GPT tokens.
     * @param goldPrice The current price of gold per troy ounce (8 decimals).
     * @param tokenPrice The current price of the payment token in USD (8 decimals).
     * @param gptAmount The amount of GPT tokens to purchase.
     * @param tokenDecimals The number of decimals the payment token uses.
     * @param tokensPerTroyOunce The number of GPT tokens that represent one troy ounce of gold.
     * @return tokenAmount The required amount of payment tokens.
     */
    function calculateTokenAmount(
        int256 goldPrice,
        int256 tokenPrice,
        uint256 gptAmount,
        uint8 tokenDecimals,
        uint256 tokensPerTroyOunce
    ) internal pure returns (uint256 tokenAmount) {
        require(goldPrice > 0, "Invalid gold price");
        require(tokenPrice > 0, "Invalid token price");
        require(tokensPerTroyOunce > 0, "Tokens per troy ounce must be greater than zero");
        require(gptAmount > 0, "GPT amount must be greater than zero");

        uint256 goldPriceUint = uint256(goldPrice); // 8 decimals
        uint256 tokenPriceUint = uint256(tokenPrice); // 8 decimals

        // Calculate the USD value of the GPT tokens (8 decimals)
        uint256 usdValue = (goldPriceUint * gptAmount) / tokensPerTroyOunce;

        // Calculate the required payment token amount
        tokenAmount = (usdValue * (10 ** tokenDecimals)) / tokenPriceUint;

        return tokenAmount;
    }

    /**
     * @dev Gets the latest prices from price feeds, ensuring they are recent enough.
     * @param goldFeed The Chainlink price feed for gold (XAU/USD).
     * @param tokenFeed The Chainlink price feed for the payment token (e.g., USDC/USD).
     * @return goldPrice The latest gold price per troy ounce in USD.
     * @return tokenPrice The latest price of the payment token in USD.
     */
    function getLatestPrices(AggregatorV3Interface goldFeed, AggregatorV3Interface tokenFeed)
        internal
        view
        returns (int256 goldPrice, int256 tokenPrice)
    {
        uint256 goldUpdatedAt;
        uint256 tokenUpdatedAt;

        // Fetch gold price (XAU/USD)
        (, goldPrice,, goldUpdatedAt,) = goldFeed.latestRoundData();
        require(goldPrice > 0, "Invalid gold price from feed");
        uint256 minAllowedTimestamp = MAX_PRICE_AGE > block.timestamp ? 0 : block.timestamp - MAX_PRICE_AGE;
        require(goldUpdatedAt >= minAllowedTimestamp, "Gold price data is stale");

        // Fetch payment token price (e.g., USDC/USD)
        (, tokenPrice,, tokenUpdatedAt,) = tokenFeed.latestRoundData();
        require(tokenPrice > 0, "Invalid token price from feed");
        require(tokenUpdatedAt >= minAllowedTimestamp, "Token price data is stale");
    }
}
