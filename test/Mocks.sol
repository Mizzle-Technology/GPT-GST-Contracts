// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "../src/vault/TradingVault.sol";

// Mock contracts
contract MockERC20 is ERC20Upgradeable, ERC20BurnableUpgradeable {
    uint8 private _decimals;

    function initialize(string memory name, string memory symbol, uint8 decimals_) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Add proper MockAggregator implementation
contract MockAggregator {
    int256 private _price;
    uint8 private constant _decimals = 8;

    constructor() {
        _price = 0;
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    // Function to get the latest answer
    function latestAnswer() external view returns (int256) {
        return _price;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            1, // roundId
            _price, // price with 8 decimals
            block.timestamp,
            block.timestamp,
            1
        );
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }
}

contract TradingVaultV2 is TradingVault {
    // Example of a new function added in V2
    function version() public pure returns (string memory) {
        return "V2";
    }
}
