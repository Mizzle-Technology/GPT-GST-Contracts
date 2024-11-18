// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

library PriceCalculationLib {
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
    function calculatePaymentTokenAmount(
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
     * @dev Calculates the required GPT token amount for purchasing GPT tokens.
     * @param goldPrice The current price of gold per troy ounce (8 decimals).
     * @param tokenPrice The current price of the payment token in USD (8 decimals).
     * @param paymentTokenAmount The amount of payment tokens to spend.
     * @param tokenDecimals The number of decimals the payment token uses.
     * @param tokensPerTroyOunce The number of GPT tokens that represent one troy ounce of gold.
     * @return gptAmount The required amount of GPT tokens.
     *
     * @dev Calculation Logic:
     * The formula to calculate the number of GPT tokens based on the payment token amount is:
     *
     * gptAmount = (paymentTokenAmount * tokenPrice * tokensPerTroyOunce) / (10^tokenDecimals * goldPrice)
     *
     * This ensures that the user receives GPT tokens proportional to their payment,
     * considering the current prices of gold and the payment token.
     *
     * Example usage within a contract
     * contract ExampleUsage {
     * using PriceCalculationLib for *;
     *
     * function example() external pure returns (uint256) {
     *     int256 goldPrice = 2000 * 10**8;          // 2_000_00000000
     *     Note: Even though USDC has 6 decimals, Chainlink price feed provides price with 8 decimals
     *     int256 tokenPrice = 1 * 10**8;           // 1_00000000
     *
     *     uint256 paymentTokenAmount = 1800 * 10**6; // 1_800_000000 (1,800 USDC with 6 decimals)
     *     uint8 tokenDecimals = 6;
     *     uint256 tokensPerTroyOunce = 10000;
     *
     *     uint256 gptAmount = PriceCalculationLib.calculateGptTokenAmount(
     *         goldPrice,
     *         tokenPrice,
     *         paymentTokenAmount,
     *         tokenDecimals,
     *         tokensPerTroyOunce
     *     );
     *
     *     return gptAmount; // Should return 9000
     *   }
     * }
     */
    function calculateGptTokenAmount(
        int256 goldPrice,
        int256 tokenPrice,
        uint256 paymentTokenAmount,
        uint8 tokenDecimals,
        uint256 tokensPerTroyOunce
    ) internal pure returns (uint256 gptAmount) {
        require(goldPrice > 0, "Invalid gold price");
        require(tokenPrice > 0, "Invalid token price");

        // Convert tokenPrice and goldPrice from int256 to uint256 after ensuring they are positive
        uint256 _tokenPrice = uint256(tokenPrice);
        uint256 _goldPrice = uint256(goldPrice);

        // Calculate GPT amount: (paymentTokenAmount * tokenPrice * tokensPerTroyOunce) / (10^tokenDecimals * goldPrice)
        gptAmount =
            (paymentTokenAmount * _tokenPrice * tokensPerTroyOunce) / (10 ** uint256(tokenDecimals) * _goldPrice);

        return gptAmount;
    }

    /**
     * @dev Gets the latest prices from price feeds, ensuring they are recent enough.
     * @param tokenFeed The Chainlink price feed for the payment token (e.g., XAU/USDC).
     * @return tokenPrice The latest price of the payment token in USD.
     * @return tokenUpdatedAt The timestamp when the token price was last updated.
     */
    function getLatestPrice(AggregatorV3Interface tokenFeed)
        internal
        view
        returns (int256 tokenPrice, uint256 tokenUpdatedAt)
    {
        // Fetch payment token price (e.g., USDC/USD)
        (, tokenPrice,, tokenUpdatedAt,) = tokenFeed.latestRoundData();
        uint256 minAllowedTimestamp = MAX_PRICE_AGE > block.timestamp ? 0 : block.timestamp - MAX_PRICE_AGE;
        require(tokenPrice > 0, "Invalid token price from feed");
        require(tokenUpdatedAt >= minAllowedTimestamp, "Token price data is stale");
    }
}
