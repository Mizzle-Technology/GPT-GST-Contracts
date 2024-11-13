// SPDX License Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";

// Mock contracts
contract MockERC20 is ERC20, ERC20Burnable {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
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
