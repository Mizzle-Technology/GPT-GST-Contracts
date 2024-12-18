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
import '../libs/LinkedMap.sol';
import '../vaults/TradingVault.sol';
import '../interface/ISalesContract.sol';
import '../utils/Errors.sol';

/**
 * @title SalesContract
 * @notice Manages GPT token sales with role-based access control
 * @dev ADMIN_ROLE: Withdrawals and emergency functions
 *      SALES_ROLE: Sales and round management
 *      Data Feeds for Testnet: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
 *      Data Feeds for Mainnet: https://data.chain.link/feeds
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
  using LinkedMap for LinkedMap.LinkedList;

  // === Constants ===
  /// @notice Number of tokens per troy ounce
  uint256 public constant TOKENS_PER_TROY_OUNCE = 10_000_000000; // 10,000 GPT tokens with 6 decimals

  /// @notice Admin role
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  /// @notice Sales role
  bytes32 public constant SALES_ROLE = keccak256('SALES_ROLE');
  /// @notice Domain type hash for EIP712
  bytes32 private constant DOMAIN_TYPE_HASH =
    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
  /// @notice Order type hash for EIP712
  bytes32 public constant ORDER_TYPEHASH =
    keccak256(
      'Order(uint256 roundId,address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken)'
    );
  /// @notice Domain separator for EIP712
  bytes32 public DOMAIN_SEPARATOR;

  // === State Variables ===
  /// @notice Trusted signer address
  address public trustedSigner;
  /// @notice GPT token contract
  GoldPackToken public gptToken;
  /// @notice Trading vault contract
  TradingVault public tradingVault;
  /// @notice Gold price feed contract
  AggregatorV3Interface public goldPriceFeed;
  /// @notice Accepted tokens mapping
  mapping(address => TokenConfig) public acceptedTokens;
  /// @notice Rounds mapping
  mapping(bytes32 => Round) public rounds;
  /// @notice Whitelisted addresses mapping
  mapping(address => bool) public whitelistedAddresses;
  /// @notice Nonces mapping
  mapping(address => uint256) public nonces;
  /// @notice Round list
  LinkedMap.LinkedList public roundList;

  /// @notice Gap for upgrade safety
  uint256[50] private __gap;

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
    if (
      _super == address(0) ||
      _admin == address(0) ||
      _sales_manager == address(0) ||
      _gptToken == address(0) ||
      _goldPriceFeed == address(0) ||
      _trustedSigner == address(0) ||
      _tradingVault == address(0)
    ) {
      revert Errors.AddressCannotBeZero();
    }

    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _grantRole(SALES_ROLE, _sales_manager);
    _setRoleAdmin(SALES_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    gptToken = GoldPackToken(_gptToken);
    tradingVault = TradingVault(_tradingVault);
    goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
    trustedSigner = _trustedSigner;

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        DOMAIN_TYPE_HASH,
        keccak256(bytes('GoldPack Token Sales')),
        keccak256(bytes('1')),
        block.chainid,
        address(this)
      )
    );
  }

  // === Modifier ===
  /**
   * @notice Modifier to check if the caller has the sales role
   */
  modifier onlySales() {
    if (!hasRole(SALES_ROLE, msg.sender)) {
      revert Errors.SalesRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @notice Modifier to check if the caller has the admin role
   */
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @notice Modifier to check if the caller has the default admin role
   */
  modifier onlyDefaultAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
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
  ) external override onlyAdmin {
    if (acceptedTokens[token].isAccepted) {
      revert Errors.TokenAlreadyAccepted(token);
    }

    if (token == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

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
  function removeAcceptedToken(address token) external onlyAdmin {
    if (!acceptedTokens[token].isAccepted) {
      revert Errors.TokenNotAccepted(token);
    }
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
  ) external override onlySales {
    if (startTime >= endTime) {
      revert Errors.InvalidTimeRange(startTime, endTime);
    }
    if (maxTokens == 0) {
      revert Errors.InvalidAmount(maxTokens);
    }
    bytes32 roundId = keccak256(abi.encodePacked(startTime, endTime, block.timestamp));
    Round memory newRound = Round({
      maxTokens: maxTokens,
      tokensSold: 0,
      isActive: false,
      startTime: startTime,
      endTime: endTime,
      stage: SaleStage.PreMarketing
    });
    roundList.add(roundId);
    rounds[roundId] = newRound;
    emit RoundCreated(roundId, maxTokens, startTime, endTime);
  }

  /**
   * @notice Activates a sale round
   * @param roundId ID of the round to activate
   */
  function _activateRound(bytes32 roundId) internal {
    if (!roundList.exists(roundId)) {
      revert Errors.RoundNotExist();
    }

    Round storage round = rounds[roundId];

    if (round.isActive) {
      revert Errors.RoundAlreadyActive();
    }
    if (block.timestamp < round.startTime) {
      revert Errors.RoundNotStarted();
    }
    if (block.timestamp > round.endTime) {
      revert Errors.RoundAlreadyEnded();
    }

    if (round.stage == SaleStage.SaleEnded) {
      revert Errors.RoundStageInvalid();
    }

    round.isActive = true;
    emit RoundActivated(roundId);
  }

  /**
   * @notice Deactivates a sale round
   * @param roundId ID of the round to deactivate
   */
  function _deactivateRound(bytes32 roundId) internal {
    if (!roundList.exists(roundId)) {
      revert Errors.RoundNotExist();
    }
    Round storage round = rounds[roundId];
    if (!round.isActive) {
      revert Errors.RoundNotActive();
    }

    round.isActive = false;
    emit RoundDeactivated(roundId);
  }

  // === Sale Stage Management ===
  /**
   * @notice Sets the sale stage for a round
   * @param _stage The stage to set
   * @param roundId The ID of the round to set the stage for
   * workflow:
   * PreMarketing -> PreSale -> SaleEnded (close the round)
   * PreMarketing -> PublicSale -> SaleEnded (close the round)
   */
  function setSaleStage(SaleStage _stage, bytes32 roundId) external override onlySales {
    Round storage round = rounds[roundId];

    // protect from not existing round
    if (!roundList.exists(roundId)) {
      revert Errors.RoundNotExist();
    }

    if (round.stage == _stage) {
      revert Errors.RoundStageInvalid();
    }

    if (round.stage == SaleStage.SaleEnded) {
      revert Errors.RoundAlreadyEnded();
    }

    if (_stage == SaleStage.PreMarketing || _stage == SaleStage.SaleEnded) {
      _deactivateRound(roundId);
    } else {
      _activateRound(roundId);
    }

    round.stage = _stage;
    emit RoundStageSet(roundId, _stage);
  }

  // === Purchase Functions ===
  /**
   * @notice Allows a whitelisted address to make a purchase during the presale stage.
   * @param order The amount of tokens to purchase.
   */
  function preSalePurchase(Order calldata order) external override nonReentrant whenNotPaused {
    Round storage currentRound = rounds[order.roundId];
    if (currentRound.stage != SaleStage.PreSale) {
      revert Errors.RoundStageInvalid();
    }

    if (!whitelistedAddresses[msg.sender]) {
      revert Errors.NotWhitelisted();
    }

    _processOrder(order);
  }

  /**
   * @notice Allows an authorized purchase during the public sale stage using a signature.
   * @param order The order struct containing the purchase details.
   */
  function authorizePurchase(Order calldata order) external override nonReentrant whenNotPaused {
    Round storage currentRound = rounds[order.roundId];
    if (currentRound.stage != SaleStage.PublicSale) {
      revert Errors.RoundStageInvalid();
    }

    _processOrder(order);
  }

  /**
   * @notice Processes an order
   * @param order The order to process
   */
  function _processOrder(Order calldata order) private {
    Round storage currentRound = rounds[order.roundId];

    if (order.buyer != msg.sender) {
      revert Errors.BuyerMismatch();
    }

    if (order.gptAmount == 0) {
      revert Errors.InvalidAmount(order.gptAmount);
    }

    if (currentRound.stage == SaleStage.SaleEnded || block.timestamp > currentRound.endTime) {
      revert Errors.RoundAlreadyEnded();
    }

    if (!currentRound.isActive) {
      revert Errors.RoundNotActive();
    }

    if (block.timestamp > order.expiry) {
      revert Errors.OrderAlreadyExpired();
    }

    if (order.nonce != nonces[order.buyer]) {
      revert Errors.InvalidNonce(order.nonce);
    }

    if (block.timestamp < currentRound.startTime) {
      revert Errors.RoundNotStarted();
    }

    if (order.gptAmount > currentRound.maxTokens) {
      revert Errors.ExceedMaxAllocation(order.gptAmount, currentRound.maxTokens);
    }

    TokenConfig storage tokenConfig = acceptedTokens[order.paymentToken];
    if (!tokenConfig.isAccepted) {
      revert Errors.TokenNotAccepted(order.paymentToken);
    }

    // Compute user order hash
    bytes32 orderHash = keccak256(
      abi.encode(
        ORDER_TYPEHASH,
        order.roundId,
        order.buyer,
        order.gptAmount,
        order.nonce,
        order.expiry,
        order.paymentToken
      )
    );

    // Verify signatures
    bool isUserSignatureValid = SalesLib.verifySignature(
      DOMAIN_SEPARATOR,
      orderHash,
      order.buyer,
      order.userSignature
    );
    if (!isUserSignatureValid) {
      revert Errors.InvalidUserSignature(order.userSignature);
    }

    bool isRelayerSignatureValid = SalesLib.verifySignature(
      DOMAIN_SEPARATOR,
      orderHash,
      trustedSigner,
      order.relayerSignature
    );
    if (!isRelayerSignatureValid) {
      revert Errors.InvalidRelayerSignature(order.relayerSignature);
    }

    // Process the purchase
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
  /**
   * @notice Emergency function to pause all contract operations
   * @dev Only callable by admin
   * @dev Emits a Paused event
   * Requirements:
   * - Caller must have admin role
   * - Contract must not already be paused
   */
  function pause() public override onlyDefaultAdmin {
    _pause();
    emit Paused(msg.sender, block.timestamp);
  }

  /**
   * @notice Emergency function to unpause all contract operations
   * @dev Only callable by admin
   * @dev Emits a Unpaused event
   */
  function unpause() public override onlyDefaultAdmin {
    _unpause();
    emit Unpaused(msg.sender, block.timestamp);
  }

  /**
   * @notice Updates the trusted signer address used for signature verification
   * @dev Only callable by admin when contract is paused
   * @param _newSigner The new signer address to set
   * @dev Emits a TrustedSignerUpdated event
   * Requirements:
   * - Caller must have admin role
   * - Contract must be paused
   * - New signer address cannot be zero
   */
  function updateTrustedSigner(address _newSigner) external override whenPaused onlyDefaultAdmin {
    if (_newSigner == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

    address oldSigner = trustedSigner;
    trustedSigner = _newSigner;

    emit TrustedSignerUpdated(oldSigner, _newSigner);
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
  function recoverERC20(address token, uint256 amount) external override onlyDefaultAdmin {
    if (token == address(gptToken)) {
      revert Errors.CannotRecoverGptToken();
    }
    if (amount == 0) {
      revert Errors.InvalidAmount(amount);
    }
    if (ERC20Upgradeable(token).balanceOf(address(this)) < amount) {
      revert Errors.InsufficientBalance(ERC20Upgradeable(token).balanceOf(address(this)), amount);
    }

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
  function addToWhitelist(address addr) external override onlySales {
    if (addr == address(0)) {
      revert Errors.AddressCannotBeZero();
    }

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
  function removeFromWhitelist(address addr) external override onlySales {
    if (addr == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (!whitelistedAddresses[addr]) {
      revert Errors.AddressNotWhitelisted(addr);
    }

    whitelistedAddresses[addr] = false;
    delete whitelistedAddresses[addr];

    emit AddressRemoved(addr);
  }

  // === UUPS Upgrade ===
  /**
   * @notice Authorizes the upgrade to a new implementation
   * @param newImplementation The address of the new implementation
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyDefaultAdmin {}

  // === View Functions ===
  /**
   * @notice GTP token amount required for a given payment token amount
   * @return The required amount of GPT tokens
   */
  function queryGptAmount(
    uint256 paymentTokenAmount,
    address paymentToken
  ) public view override returns (uint256) {
    if (paymentTokenAmount <= 0) {
      revert Errors.InvalidAmount(paymentTokenAmount);
    }
    if (paymentToken == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    TokenConfig storage tokenConfig = acceptedTokens[paymentToken];
    if (!tokenConfig.isAccepted) {
      revert Errors.TokenNotAccepted(paymentToken);
    }

    (int256 goldPrice, ) = CalculationLib.getLatestPrice(goldPriceFeed);
    (int256 tokenPrice, ) = CalculationLib.getLatestPrice(tokenConfig.priceFeed);

    return
      CalculationLib.calculateGptAmount(
        goldPrice,
        tokenPrice,
        paymentTokenAmount,
        tokenConfig.decimals,
        TOKENS_PER_TROY_OUNCE
      );
  }

  /**
   * @notice Payment token amount required for a given GPT token amount
   * @return The required amount of payment tokens
   */
  function queryPaymentTokenAmount(
    uint256 gptAmount,
    address paymentToken
  ) external view override returns (uint256) {
    if (gptAmount <= 0) {
      revert Errors.InvalidAmount(gptAmount);
    }
    if (paymentToken == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    TokenConfig storage tokenConfig = acceptedTokens[paymentToken];
    if (!tokenConfig.isAccepted) {
      revert Errors.TokenNotAccepted(paymentToken);
    }
    (int256 goldPrice, ) = CalculationLib.getLatestPrice(goldPriceFeed);
    (int256 tokenPrice, ) = CalculationLib.getLatestPrice(tokenConfig.priceFeed);
    return
      CalculationLib.calculatePaymentTokenAmount(
        goldPrice,
        tokenPrice,
        gptAmount,
        tokenConfig.decimals,
        TOKENS_PER_TROY_OUNCE
      );
  }

  /**
   * @notice Returns the current sale stage of a round
   * @return The current sale stage
   */
  function RoundStage(bytes32 roundId) external view returns (SaleStage) {
    return rounds[roundId].stage;
  }

  /**
   * @notice Returns the current round ID
   * @return The current round ID
   */
  function latestRoundId() external view returns (bytes32) {
    return roundList.getTail();
  }
}
