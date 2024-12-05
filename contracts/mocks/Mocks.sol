// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '../../contracts/vaults/TradingVault.sol';
import '../../contracts/vaults/BurnVault.sol';
import '../../contracts/libs/CalculationLib.sol';
import '../../contracts/rewards/RewardDistribution.sol';
// Mock contracts
/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing purposes
 * @dev Implements ERC20BurnableUpgradeable for testing
 */
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

  /// @notice Mints new tokens to an address
  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

/**
 * @title MockAggregator
 * @notice Mock implementation of Chainlink AggregatorV3Interface
 * @dev Used for testing price feed functionality
 */
contract MockAggregator {
  int256 private _price;
  uint8 private constant _decimals = 8;
  uint256 private _timestamp;
  uint80 private _roundId;
  uint256 private _startedAt;
  uint80 private _answeredInRound;

  /// @notice Initializes the mock aggregator
  constructor() {
    _price = 0;
  }

  /// @notice Sets the price of the mock aggregator
  function setPrice(int256 price) external {
    _price = price;
  }

  /// @notice Sets the latest round data for the mock aggregator
  function setLatestRoundData(int256 price, uint256 timestamp) external {
    _price = price;
    _timestamp = timestamp;
  }

  /// @notice Sets the round data for the mock aggregator
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

  /// @notice Gets the latest answer from the mock aggregator
  function latestAnswer() external view returns (int256) {
    return _price;
  }

  /// @notice Gets the latest round data from the mock aggregator
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (_roundId, _price, _startedAt, _timestamp, _answeredInRound);
  }

  /// @notice Gets the round data from the mock aggregator
  function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
    return (_roundId, _price, _startedAt, _timestamp, _answeredInRound);
  }

  /// @notice Gets the decimals of the mock aggregator
  function decimals() external pure returns (uint8) {
    return _decimals;
  }
}

/**
 * @title TradingVaultV2
 * @notice Mock implementation of TradingVault for testing
 * @dev Used for testing upgradeability
 */
contract TradingVaultV2 is TradingVault {
  /// @notice Gets the version of the TradingVaultV2
  function version() public pure returns (string memory) {
    return 'V2';
  }
}

/**
 * @title IReentrancyAttack
 * @notice Interface for the callback
 * @dev Used for testing reentrancy
 */
interface IReentrancyAttack {
  function reenter() external;
}

/**
 * @title ReentrantERC20
 * @notice Reentrant ERC20 token for testing
 * @dev Used for testing reentrancy
 */
contract ReentrantERC20 is ERC20Upgradeable, ERC20BurnableUpgradeable {
  uint8 private _customDecimals;

  /// @notice Initializes the reentrant ERC20 token
  function initialize(
    string memory name,
    string memory symbol,
    uint8 decimals_
  ) public initializer {
    __ERC20_init(name, symbol);
    __ERC20Burnable_init();
    _customDecimals = decimals_;
  }

  /// @notice Gets the decimals of the reentrant ERC20 token
  function decimals() public view override returns (uint8) {
    return _customDecimals;
  }

  /// @notice Mints new tokens to an address
  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }

  /// @notice Burns tokens from an address
  function burn(uint256 amount) public override {
    super.burn(amount);
    // If the caller is a contract, invoke reenter
    if (isContract(msg.sender)) {
      IReentrancyAttack(msg.sender).reenter();
    }
  }

  /// @notice Override transferFrom to include a callback for reentrancy
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

  /// @notice Helper function to check if an address is a contract
  function isContract(address account) internal view returns (bool) {
    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }
}

/**
 * @title MaliciousContract
 * @notice Malicious contract for reentrancy tests
 * @dev Used for testing reentrancy
 */
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

  /// @notice Attacks the depositTokens function
  function attackDeposit(uint256 amount) public {
    token.approve(address(vault), amount);
    vault.depositTokens(amount, token);
  }

  /// @notice Reenters the contract
  function reenter() external override {
    if (!reentered) {
      reentered = true;
      // Attempt to reenter depositTokens
      vault.depositTokens(1, token);

      // Attempt to reenter burnTokens
      vault.burnAllTokens(targetAccount, token);
    }
  }

  /// @notice Attacks the burnTokens function
  function attackBurn(address account, uint256 amount) public {
    targetAccount = account;
    vault.burnTokens(account, amount, token);
  }
}

/**
 * @title TestCalculationLib
 * @notice Test contract for CalculationLib functions
 * @dev Used for testing CalculationLib
 */
contract TestCalculationLib {
  using CalculationLib for *;

  /// @notice Calculates GPT amount from payment token amount
  function calculateGptAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 paymentTokenAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) public pure returns (uint256) {
    return
      CalculationLib.calculateGptAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenDecimals,
        tokensPerTroyOunce
      );
  }

  /// @notice Calculates payment token amount from GPT amount
  function calculatePaymentTokenAmount(
    int256 goldPrice,
    int256 tokenPrice,
    uint256 gptAmount,
    uint8 tokenDecimals,
    uint256 tokensPerTroyOunce
  ) public pure returns (uint256) {
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

/**
 * @title RewardDistributionV2
 * @notice Mock V2 Implementation for Upgradeability Test
 * @dev Used for testing upgradeability
 * @custom:oz-upgrades-from RewardDistribution.sol:RewardDistribution
 */
contract RewardDistributionV2 is RewardDistribution {
  uint256 private newVariable;

  /// @notice Sets the new variable
  function setNewVariable(uint256 _value) external {
    newVariable = _value;
  }

  /// @notice Gets the new variable
  function getNewVariable() external view returns (uint256) {
    return newVariable;
  }
}
