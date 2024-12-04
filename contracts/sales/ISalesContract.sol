// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';

interface ISalesContract {
  // === Structs and Enums ===
  struct TokenConfig {
    bool isAccepted;
    AggregatorV3Interface priceFeed;
    uint8 decimals;
  }

  struct Round {
    uint256 maxTokens;
    uint256 tokensSold;
    bool isActive;
    uint256 startTime;
    uint256 endTime;
    SaleStage stage;
  }

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

  enum SaleStage {
    PreMarketing,
    PreSale,
    PublicSale,
    SaleEnded
  }

  // === Events ===
  event TokensPurchased(
    address indexed buyer,
    uint256 amount,
    uint256 tokenSpent,
    address indexed paymentToken,
    bool isPresale
  );
  event RoundCreated(
    bytes32 indexed roundId,
    uint256 maxTokens,
    uint256 startTime,
    uint256 endTime
  );
  event RoundActivated(bytes32 indexed roundId);
  event RoundDeactivated(bytes32 indexed roundId);
  event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);
  event PriceAgeUpdated(uint256 oldAge, uint256 newAge);
  event Paused(address indexed pauser, uint256 timestamp);
  event Unpaused(address indexed unpauser, uint256 timestamp);
  event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);
  event ETHRecovered(uint256 amount, address indexed recipient);
  event AddressWhitelisted(address indexed addr);
  event AddressRemoved(address indexed addr);
  event RoundStageSet(bytes32 indexed roundId, SaleStage stage);

  // === Token Management ===
  function addAcceptedToken(address token, address priceFeed, uint8 decimals) external;
  function removeAcceptedToken(address token) external;

  // === Sale Stage Management ===
  function createRound(uint256 maxTokens, uint256 startTime, uint256 endTime) external;
  function setSaleStage(SaleStage _stage, bytes32 roundId) external;

  // === Purchase Functions ===
  function preSalePurchase(Order calldata order) external;
  function authorizePurchase(Order calldata order) external;

  // === View Functions ===
  function RoundStage(bytes32 roundId) external view returns (SaleStage);

  // === Emergency Functions ===
  function pause() external;
  function unpause() external;

  // === Recovery Functions ===
  function recoverERC20(address token, uint256 amount) external;

  // === Whitelist Functions ===
  function addToWhitelist(address addr) external;
  function removeFromWhitelist(address addr) external;
}
