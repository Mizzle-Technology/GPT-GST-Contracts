// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// OpenZeppelin imports
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
// Chainlink imports
import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';

// Local imports
import '../tokens/GoldPackToken.sol';
import '../libs/SalesLib.sol';
import '../vaults/TradingVault.sol';
import './ISalesContract.sol';

/**
 * @title SalesContract
 * @notice Manages GPT token sales with role-based access control
 * @dev ADMIN_ROLE: Withdrawals and emergency functions
 *      SALES_ROLE: Sales and round management
 *      Data Feeds for Testnet: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
 *      Data Feeds for Mainnet: https://data.chain.link/feeds
 * Emits an {AddressWhitelisted} event.
 */
contract SalesContract is
  Initializable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  ISalesContract
{
  using SafeERC20 for ERC20Upgradeable;
  using SalesLib for *;

  // === Constants ===
  uint256 public constant TOKENS_PER_TROY_OUNCE = 10_000_000000; // 10,000 GPT tokens with 6 decimals

  /// @dev Maximum time allowed between price updates
  uint256 public constant MAX_PRICE_AGE = 1 hours;

  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant SALES_ROLE = keccak256('SALES_ROLE');
  bytes32 private constant DOMAIN_TYPE_HASH =
    keccak256(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
  bytes32 public constant USER_ORDER_TYPEHASH =
    keccak256(
      'Order(uint256 roundId,address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,uint256 chainId)'
    );
  bytes32 public constant RELAYER_ORDER_TYPEHASH =
    keccak256(
      'RelayerOrder(uint256 roundId,address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,bytes userSignature,uint256 chainId)'
    );
  bytes32 public DOMAIN_SEPARATOR;

  // === State Variables ===
  uint256 public maxPurchaseAmount;
  uint256 public totalTokensSold;
  uint256 public currentRoundId;
  uint256 public nextRoundId;
  uint256 private chainId;
  string public pauseReason;
  address public trustedSigner;
  GoldPackToken public gptToken;
  TradingVault public tradingVault;
  AggregatorV3Interface internal goldPriceFeed;
  SaleStage public currentStage;

  mapping(address => TokenConfig) public acceptedTokens;
  mapping(uint256 => Round) public rounds;
  mapping(address => bool) public whitelistedAddresses;
  mapping(address => uint256) public nonces;
  mapping(bytes32 => uint256) public timelockExpiries;

  // === Constructor ===

  /**
   * @notice Contract constructor
   * @param _gptToken GPT token address
   * @param _goldPriceFeed Chainlink gold price feed address
   * @param _trustedSigner Address that signs purchase authorizations
   */
  function initialize(
    address _super,
    address _admin,
    address _sales_manager,
    address _gptToken,
    address _goldPriceFeed,
    address _trustedSigner,
    address _tradingVault
  ) public initializer {
    require(_gptToken != address(0), 'Invalid GPT address');
    require(_goldPriceFeed != address(0), 'Invalid price feed address');
    require(_trustedSigner != address(0), 'Invalid signer address');

    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _grantRole(SALES_ROLE, _sales_manager);
    _setRoleAdmin(SALES_ROLE, ADMIN_ROLE);
    // _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    gptToken = GoldPackToken(_gptToken);
    tradingVault = TradingVault(_tradingVault);
    goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
    trustedSigner = _trustedSigner;
    currentStage = SaleStage.PreMarketing;

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        DOMAIN_TYPE_HASH,
        keccak256(bytes('GPTSales')),
        keccak256(bytes('1')),
        block.chainid,
        address(this)
      )
    );

    chainId = block.chainid;
  }

  // === Token Management ===
  /**
   * @notice Adds a new accepted payment token
   * @param token Address of the payment token
   * @param priceFeed Address of the Chainlink price feed for the token
   * @param decimals Number of decimals the token uses
   */
  function addAcceptedToken(
    address token,
    address priceFeed,
    uint8 decimals
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    require(token != address(0), 'Invalid token address');
    acceptedTokens[token] = TokenConfig({
      isAccepted: true,
      priceFeed: AggregatorV3Interface(priceFeed),
      decimals: decimals
    });
  }

  /**
   * @notice Removes an accepted payment token
   * @param token Address of the token to remove
   */
  function removeAcceptedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(acceptedTokens[token].isAccepted, 'Token not accepted');
    delete acceptedTokens[token];
  }

  // === Round Management ===
  /**
   * @notice Creates a new sale round
   * @param maxTokens Maximum number of tokens available in the round
   * @param startTime Start time of the round
   * @param endTime End time of the round
   */
  function createRound(
    uint256 maxTokens,
    uint256 startTime,
    uint256 endTime
  ) external override onlyRole(SALES_ROLE) {
    require(startTime < endTime, 'Invalid round time');
    currentRoundId = nextRoundId;
    rounds[currentRoundId] = Round({
      maxTokens: maxTokens,
      tokensSold: 0,
      isActive: false,
      startTime: startTime,
      endTime: endTime
    });
    emit RoundCreated(currentRoundId, maxTokens, startTime, endTime);
    nextRoundId++;
  }

  /**
   * @notice Activates a sale round
   * @param roundId ID of the round to activate
   */
  function activateRound(uint256 roundId) external override onlyRole(SALES_ROLE) {
    require(roundId < nextRoundId, 'Round does not exist');
    Round storage round = rounds[roundId];
    require(!round.isActive, 'Round already active');
    require(block.timestamp >= round.startTime, 'Round not started');
    require(block.timestamp <= round.endTime, 'Round ended');

    round.isActive = true;
    emit RoundActivated(roundId);
  }

  /**
   * @notice Deactivates a sale round
   * @param roundId ID of the round to deactivate
   */
  function deactivateRound(uint256 roundId) external override onlyRole(SALES_ROLE) {
    require(roundId < nextRoundId, 'Round does not exist');
    Round storage round = rounds[roundId];
    require(round.isActive, 'Round not active');

    round.isActive = false;
    emit RoundDeactivated(roundId);
  }

  // === Sale Stage Management ===
  /**
   * @notice Sets the current sale stage
   * @param _stage The new sale stage
   */
  function setSaleStage(SaleStage _stage) external override onlyRole(SALES_ROLE) {
    currentStage = _stage;
  }

  // === Purchase Functions ===
  /**
   * @notice Allows a whitelisted address to make a purchase during the presale stage.
   * @param order The amount of tokens to purchase.
   */
  function preSalePurchase(
    Order calldata order
  ) external override nonReentrant whenNotPaused {
    require(currentStage == SaleStage.PreSale, 'Presale not active');
    require(whitelistedAddresses[msg.sender], 'Not whitelisted');
    require(order.buyer == msg.sender, 'Buyer mismatch'); // Added buyer verification

    TokenConfig storage tokenConfig = acceptedTokens[order.paymentToken];
    require(tokenConfig.isAccepted, 'Token not accepted');

    // Compute user order hash
    bytes32 userOrderHash = keccak256(
      abi.encode(
        USER_ORDER_TYPEHASH,
        order.roundId,
        order.buyer,
        order.gptAmount,
        order.nonce,
        order.expiry,
        order.paymentToken,
        chainId
      )
    );

    // Verify user signature using SalesLib
    require(
      SalesLib.verifyUserSignature(
        DOMAIN_SEPARATOR,
        userOrderHash,
        order.buyer,
        order.userSignature
      ),
      'Invalid user signature'
    );

    // Compute relayer order hash
    bytes32 relayerOrderHash = keccak256(
      abi.encode(
        RELAYER_ORDER_TYPEHASH,
        order.roundId,
        order.buyer,
        order.gptAmount,
        order.nonce,
        order.expiry,
        order.paymentToken,
        order.userSignature,
        chainId
      )
    );

    // Verify relayer signature using SalesLib
    require(
      SalesLib.verifyRelayerSignature(
        DOMAIN_SEPARATOR,
        relayerOrderHash,
        trustedSigner,
        order.relayerSignature
      ),
      'Invalid relayer signature'
    );

    // Fetch the current round
    ISalesContract.Round storage currentRound = rounds[order.roundId];
    require(currentRound.isActive, 'Round is not active');

    // Process the purchase using SalesLib
    SalesLib.processPurchase(
      goldPriceFeed,
      tokenConfig,
      tradingVault,
      gptToken,
      currentRound,
      order.gptAmount,
      order.paymentToken,
      order.buyer,
      TOKENS_PER_TROY_OUNCE
    );

    nonces[order.buyer]++;
  }

  /**
   * @notice Allows an authorized purchase during the public sale stage using a signature.
   * @param order The order struct containing the purchase details.
   */
  function authorizePurchase(
    Order calldata order
  ) external override nonReentrant whenNotPaused {
    require(currentStage == SaleStage.PublicSale, 'Public sale not active');
    require(order.nonce == nonces[order.buyer], 'Invalid nonce');
    require(block.timestamp <= order.expiry, 'Signature expired');

    TokenConfig storage tokenConfig = acceptedTokens[order.paymentToken];
    require(tokenConfig.isAccepted, 'Token not accepted');

    // Compute user order hash
    bytes32 userOrderHash = keccak256(
      abi.encode(
        USER_ORDER_TYPEHASH,
        order.roundId,
        order.buyer,
        order.gptAmount,
        order.nonce,
        order.expiry,
        order.paymentToken,
        chainId
      )
    );

    // Verify user signature using SalesLib
    require(
      SalesLib.verifyUserSignature(
        DOMAIN_SEPARATOR,
        userOrderHash,
        order.buyer,
        order.userSignature
      ),
      'Invalid user signature'
    );

    // Compute relayer order hash
    bytes32 relayerOrderHash = keccak256(
      abi.encode(
        RELAYER_ORDER_TYPEHASH,
        order.roundId,
        order.buyer,
        order.gptAmount,
        order.nonce,
        order.expiry,
        order.paymentToken,
        order.userSignature,
        chainId
      )
    );

    // Verify relayer signature using SalesLib
    require(
      SalesLib.verifyRelayerSignature(
        DOMAIN_SEPARATOR,
        relayerOrderHash,
        trustedSigner,
        order.relayerSignature
      ),
      'Invalid relayer signature'
    );

    // Fetch the current round
    ISalesContract.Round storage currentRound = rounds[order.roundId];
    require(currentRound.isActive, 'Round is not active');

    // Process the purchase using SalesLib
    SalesLib.processPurchase(
      goldPriceFeed,
      tokenConfig,
      tradingVault,
      gptToken,
      currentRound,
      order.gptAmount,
      order.paymentToken,
      order.buyer,
      TOKENS_PER_TROY_OUNCE
    );

    nonces[order.buyer]++;
  }

  // === Emergency Functions ===
  function pause() public override onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
    emit Paused(msg.sender, block.timestamp);
  }

  function unpause() public override onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
    emit Unpaused(msg.sender, block.timestamp);
  }

  // === Recovery Functions ===
  /**
   * @notice Recovers stuck ERC20 tokens from the contract
   * @param token The token to recover
   * @param amount The amount to recover
   * Requirements:
   * - Only callable by admin
   * - Cannot recover GPT token
   * - Amount must be <= balance
   */
  function recoverERC20(
    address token,
    uint256 amount
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    require(token != address(gptToken), 'Cannot recover GPT token');
    require(amount > 0, 'Amount must be greater than 0');
    require(
      ERC20Upgradeable(token).balanceOf(address(this)) >= amount,
      'Insufficient balance'
    );

    // check allowance
    uint256 allowance = ERC20Upgradeable(token).allowance(address(this), msg.sender);
    require(allowance >= amount, 'Token allowance too low');

    ERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    emit TokenRecovered(token, amount, msg.sender);
  }

  // === Whitelist Functions ===
  /**
   * @notice Adds an address to the whitelist
   * @param addr The address to add
   * Requirements:
   * - Only admin can call
   */
  function addToWhitelist(address addr) external override onlyRole(SALES_ROLE) {
    require(addr != address(0), 'Invalid address');

    whitelistedAddresses[addr] = true;

    emit AddressWhitelisted(addr);
  }

  /**
   * @notice Removes an address from the whitelist
   * @param addr The address to remove
   * /**
   * @notice Removes an address from the whitelist
   * @param addr The address to remove
   * Requirements:
   * - Only admin can call
   * Emits a {WhitelistRemoved} event.
   */
  function removeFromWhitelist(address addr) external override onlyRole(SALES_ROLE) {
    require(addr != address(0), 'Invalid address');
    require(whitelistedAddresses[addr], 'Address not whitelisted');

    whitelistedAddresses[addr] = false;
    delete whitelistedAddresses[addr];

    emit AddressRemoved(addr);
  }

  // === UUPS Upgrade ===
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // === View Functions ===
  /**
   * @notice GTP token amount required for a given payment token amount
   * @return gptAmount The required amount of GPT tokens
   */
  function queryGptAmount(
    uint256 paymentTokenAmount,
    address paymentToken
  ) public view returns (uint256 gptAmount) {
    require(paymentTokenAmount > 0, 'Amount must be greater than 0');
    require(paymentToken != address(0), 'Invalid token address');
    TokenConfig storage tokenConfig = acceptedTokens[paymentToken];
    require(tokenConfig.isAccepted, 'Token not accepted');
    // check if the token config is existed

    (int256 goldPrice, ) = CalculationLib.getLatestPrice(goldPriceFeed);
    (int256 tokenPrice, ) = CalculationLib.getLatestPrice(tokenConfig.priceFeed);

    return
      CalculationLib.calculateGptTokenAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenConfig.decimals,
        TOKENS_PER_TROY_OUNCE
      );
  }
}
