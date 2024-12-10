// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';

/**
 * @title ISalesContract
 * @dev Interface for the SalesContract
 */
interface ISalesContract {
  // === Structs and Enums ===
  /// @notice Token configuration
  struct TokenConfig {
    bool isAccepted;
    AggregatorV3Interface priceFeed;
    uint8 decimals;
  }

  /// @notice Round configuration
  struct Round {
    uint256 maxTokens;
    uint256 tokensSold;
    bool isActive;
    uint256 startTime;
    uint256 endTime;
    SaleStage stage;
  }

  /// @notice Order configuration
  struct Order {
    bytes32 roundId;
    address buyer;
    uint256 gptAmount;
    uint256 nonce;
    uint256 expiry;
    address paymentToken;
    bytes userSignature;
    bytes relayerSignature;
  }

  /// @notice Sale stages
  enum SaleStage {
    PreMarketing,
    PreSale,
    PublicSale,
    SaleEnded
  }

  // === Events ===
  /// @notice Tokens purchased
  event TokensPurchased(
    address indexed buyer,
    uint256 amount,
    uint256 tokenSpent,
    address indexed paymentToken,
    bool isPresale
  );
  /// @notice Round created
  event RoundCreated(
    bytes32 indexed roundId,
    uint256 maxTokens,
    uint256 startTime,
    uint256 endTime
  );
  /// @notice Round activated
  event RoundActivated(bytes32 indexed roundId);
  /// @notice Round deactivated
  event RoundDeactivated(bytes32 indexed roundId);
  /// @notice Trusted signer updated
  event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);
  /// @notice Price age updated
  event PriceAgeUpdated(uint256 oldAge, uint256 newAge);
  /// @notice Paused
  event Paused(address indexed pauser, uint256 timestamp);
  /// @notice Unpaused
  event Unpaused(address indexed unpauser, uint256 timestamp);
  /// @notice Token recovered
  event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);
  /// @notice ETH recovered
  event ETHRecovered(uint256 amount, address indexed recipient);
  /// @notice Address whitelisted
  event AddressWhitelisted(address indexed addr);
  /// @notice Address removed
  event AddressRemoved(address indexed addr);
  /// @notice Round stage set
  event RoundStageSet(bytes32 indexed roundId, SaleStage stage);

  // === Token Management ===
  /// @notice Adds an accepted token
  function addAcceptedToken(address token, address priceFeed, uint8 decimals) external;
  /// @notice Removes an accepted token
  function removeAcceptedToken(address token) external;

  // === Sale Stage Management ===
  /// @notice Creates a new round
  function createRound(uint256 maxTokens, uint256 startTime, uint256 endTime) external;
  /// @notice Sets the sale stage for a round
  function setSaleStage(SaleStage _stage, bytes32 roundId) external;

  // === Purchase Functions ===
  /// @notice Pre-sale purchase
  function preSalePurchase(Order calldata order) external;
  /// @notice Authorizes a purchase
  function authorizePurchase(Order calldata order) external;

  // === View Functions ===
  /// @notice Returns the sale stage for a round
  function RoundStage(bytes32 roundId) external view returns (SaleStage);

  // === Emergency Functions ===
  /// @notice Pauses the contract
  function pause() external;
  /// @notice Unpauses the contract
  function unpause() external;

  // === Recovery Functions ===
  /// @notice Recovers ERC20 tokens
  function recoverERC20(address token, uint256 amount) external;

  // === Whitelist Functions ===
  /// @notice Adds an address to the whitelist
  function addToWhitelist(address addr) external;
  /// @notice Removes an address from the whitelist
  function removeFromWhitelist(address addr) external;
}
