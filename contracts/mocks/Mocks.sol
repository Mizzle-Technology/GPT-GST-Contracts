// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '../vaults/TradingVault.sol';
import '../vaults/BurnVault.sol';
import '../libs/CalculationLib.sol';
import '../rewards/RewardDistribution.sol';
// Mock contracts
contract MockERC20 is ERC20BurnableUpgradeable {
  uint8 private _decimals;

  function initialize(
    string memory name,
    string memory symbol,
    uint8 decimals_
  ) public initializer {
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
  uint256 private _timestamp;
  uint80 private _roundId;
  uint256 private _startedAt;
  uint80 private _answeredInRound;

  constructor() {
    _price = 0;
  }

  function setPrice(int256 price) external {
    _price = price;
  }

  function setLatestRoundData(int256 price, uint256 timestamp) external {
    _price = price;
    _timestamp = timestamp;
  }

  function setRoundData(
    uint80 roundId,
    int256 price,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  ) external {
    _roundId = roundId;
    _price = price;
    _startedAt = startedAt;
    _timestamp = updatedAt;
    _answeredInRound = answeredInRound;
  }

  // Function to get the latest answer
  function latestAnswer() external view returns (int256) {
    return _price;
  }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return (_roundId, _price, _startedAt, _timestamp, _answeredInRound);
  }

  function getRoundData(
    uint80
  )
    external
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    _roundId = roundId;
    _startedAt = startedAt;
    _timestamp = updatedAt;
    _answeredInRound = answeredInRound;
    return (_roundId, _price, _startedAt, _timestamp, _answeredInRound);
  }

  function decimals() external pure returns (uint8) {
    return _decimals;
  }
}

contract TradingVaultV2 is TradingVault {
  // Example of a new function added in V2
  function version() public pure returns (string memory) {
    return 'V2';
  }
}

// Interface for the callback
interface IReentrancyAttack {
  function reenter() external;
}

// Reentrant ERC20 Token for testing
contract ReentrantERC20 is ERC20Upgradeable, ERC20BurnableUpgradeable {
  uint8 private _customDecimals;

  function initialize(
    string memory name,
    string memory symbol,
    uint8 decimals_
  ) public initializer {
    __ERC20_init(name, symbol);
    __ERC20Burnable_init();
    _customDecimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return _customDecimals;
  }

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }

  function burn(uint256 amount) public override {
    super.burn(amount);
    // If the caller is a contract, invoke reenter
    if (isContract(msg.sender)) {
      IReentrancyAttack(msg.sender).reenter();
    }
  }

  // Override transferFrom to include a callback for reentrancy
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    // Normal transferFrom logic
    _spendAllowance(from, _msgSender(), amount);
    _transfer(from, to, amount);

    // If the sender is a contract, invoke the reenter function
    if (isContract(from)) {
      IReentrancyAttack(from).reenter();
    }

    return true;
  }

  // Helper function to check if an address is a contract
  function isContract(address account) internal view returns (bool) {
    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }
}

// Malicious contract for reentrancy tests
contract MaliciousContract is IReentrancyAttack {
  BurnVault public vault;
  ReentrantERC20 public token;
  bool public reentered;
  address public targetAccount;

  constructor(BurnVault _vault, ReentrantERC20 _token) {
    vault = _vault;
    token = _token;
    reentered = false;
  }

  function attackDeposit(uint256 amount) public {
    token.approve(address(vault), amount);
    vault.depositTokens(amount, token);
  }

  // This function will be called during transferFrom in ReentrantERC20
  function reenter() external override {
    if (!reentered) {
      reentered = true;
      // Attempt to reenter depositTokens
      vault.depositTokens(1, token);

      // Attempt to reenter burnTokens
      vault.burnAllTokens(targetAccount, token);
    }
  }

  function attackBurn(address account, uint256 amount) public {
    targetAccount = account;
    vault.burnTokens(account, amount, token);
  }
}

contract TestCalculationLib {
  using CalculationLib for *;
  function calculateGptAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 paymentTokenAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) public pure returns (uint256 gptAmount) {
    return
      CalculationLib.calculateGptAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenDecimals,
        tokensPerTroyOunce
      );
  }

  function calculatePaymentTokenAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 gptAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) public pure returns (uint256 tokenAmount) {
    return
      CalculationLib.calculatePaymentTokenAmount(
        goldPrice,
        tokenPrice,
        gptAmount,
        tokenDecimals,
        tokensPerTroyOunce
      );
  }
}
// Mock V2 Implementation for Upgradeability Test
/// @custom:oz-upgrades-from RewardDistribution.sol:RewardDistribution
contract RewardDistributionV2 is RewardDistribution {
  uint256 private newVariable;

  function setNewVariable(uint256 _value) external {
    newVariable = _value;
  }

  function getNewVariable() external view returns (uint256) {
    return newVariable;
  }
}
