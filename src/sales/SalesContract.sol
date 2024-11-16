// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// OpenZeppelin imports
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// Chainlink imports
import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// Local imports
import "../tokens/GoldPackToken.sol";
import "../libs/PriceCalculator.sol";
import "../vault/TradingVault.sol";

/**
 * @title SalesContract
 * @notice Manages GPT token sales with role-based access control
 * @dev ADMIN_ROLE: Withdrawals and emergency functions
 *      SALES_MANAGER_ROLE: Sales and round management
 *      Data Feeds for Testnet: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
 *      Data Feeds for Mainnet: https://data.chain.link/feeds
 * Emits an {AddressWhitelisted} event.
 */
contract SalesContract is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for ERC20Upgradeable;
    using PriceCalculator for *;

    // === Constants ===
    uint256 public constant TOKENS_PER_TROY_OUNCE = 10_000_000000; // 10,000 GPT tokens with 6 decimals

    /// @dev Maximum time allowed between price updates
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SALES_MANAGER_ROLE = keccak256("SALES_MANAGER_ROLE");
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant USER_ORDER_TYPEHASH = keccak256(
        "Order(uint256 roundId,address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,uint256 chainId)"
    );
    bytes32 public constant RELAYER_ORDER_TYPEHASH = keccak256(
        "RelayerOrder(uint256 roundId,address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,bytes userSignature,uint256 chainId)"
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
    }

    enum SaleStage {
        PreMarketing,
        PreSale,
        PublicSale,
        SaleEnded
    }

    struct Order {
        uint256 roundId;
        address buyer;
        uint256 gptAmount;
        uint256 nonce;
        uint256 expiry;
        address paymentToken;
        bytes userSignature;
        bytes relayerSignature;
    }

    // === Events ===
    event TokensPurchased(
        address indexed buyer, uint256 amount, uint256 tokenSpent, address indexed paymentToken, bool isPresale
    );
    event RoundCreated(uint256 indexed roundId, uint256 maxTokens, uint256 startTime, uint256 endTime);
    event RoundActivated(uint256 indexed roundId);
    event RoundDeactivated(uint256 indexed roundId);
    event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event PriceAgeUpdated(uint256 oldAge, uint256 newAge);
    event Paused(address indexed pauser, uint256 timestamp);
    event Unpaused(address indexed unpauser, uint256 timestamp);
    event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);
    event ETHRecovered(uint256 amount, address indexed recipient);
    event AddressWhitelisted(address indexed addr);
    event AddressRemoved(address indexed addr);

    // === Constructor ===

    /**
     * @notice Contract constructor
     * @param _gptToken GPT token address
     * @param _goldPriceFeed Chainlink gold price feed address
     * @param _trustedSigner Address that signs purchase authorizations
     */
    function initialize(address _gptToken, address _goldPriceFeed, address _trustedSigner, address _tradingVault)
        public
        initializer
    {
        require(_gptToken != address(0), "Invalid GPT address");
        require(_goldPriceFeed != address(0), "Invalid price feed address");
        require(_trustedSigner != address(0), "Invalid signer address");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SALES_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

        gptToken = GoldPackToken(_gptToken);
        tradingVault = TradingVault(_tradingVault);
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
        trustedSigner = _trustedSigner;
        currentStage = SaleStage.PreMarketing;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, keccak256(bytes("GPTSales")), keccak256(bytes("1")), block.chainid, address(this)
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
    function addAcceptedToken(address token, address priceFeed, uint8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token address");
        acceptedTokens[token] =
            TokenConfig({isAccepted: true, priceFeed: AggregatorV3Interface(priceFeed), decimals: decimals});
    }

    /**
     * @notice Removes an accepted payment token
     * @param token Address of the token to remove
     */
    function removeAcceptedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(acceptedTokens[token].isAccepted, "Token not accepted");
        delete acceptedTokens[token];
    }

    // === Round Management ===
    /**
     * @notice Creates a new sale round
     * @param maxTokens Maximum number of tokens available in the round
     * @param startTime Start time of the round
     * @param endTime End time of the round
     */
    function createRound(uint256 maxTokens, uint256 startTime, uint256 endTime) external onlyRole(SALES_MANAGER_ROLE) {
        require(startTime < endTime, "Invalid round time");
        currentRoundId = nextRoundId;
        rounds[currentRoundId] =
            Round({maxTokens: maxTokens, tokensSold: 0, isActive: false, startTime: startTime, endTime: endTime});
        emit RoundCreated(currentRoundId, maxTokens, startTime, endTime);
        nextRoundId++;
    }

    /**
     * @notice Activates a sale round
     * @param roundId ID of the round to activate
     */
    function activateRound(uint256 roundId) external onlyRole(SALES_MANAGER_ROLE) {
        require(roundId < nextRoundId, "Round does not exist");
        Round storage round = rounds[roundId];
        require(!round.isActive, "Round already active");
        require(block.timestamp >= round.startTime, "Round not started");
        require(block.timestamp <= round.endTime, "Round ended");

        round.isActive = true;
        emit RoundActivated(roundId);
    }

    /**
     * @notice Deactivates a sale round
     * @param roundId ID of the round to deactivate
     */
    function deactivateRound(uint256 roundId) external onlyRole(SALES_MANAGER_ROLE) {
        require(roundId < nextRoundId, "Round does not exist");
        Round storage round = rounds[roundId];
        require(round.isActive, "Round not active");

        round.isActive = false;
        emit RoundDeactivated(roundId);
    }

    // === Sale Stage Management ===
    /**
     * @notice Sets the current sale stage
     * @param _stage The new sale stage
     */
    function setSaleStage(SaleStage _stage) external onlyRole(SALES_MANAGER_ROLE) {
        currentStage = _stage;
    }

    // === Purchase Functions ===
    /**
     * @notice Allows a whitelisted address to make a purchase during the presale stage.
     * @param order The amount of tokens to purchase.
     */
    function preSalePurchase(Order calldata order) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PreSale, "Presale not active");
        require(whitelistedAddresses[msg.sender], "Not whitelisted");
        require(order.buyer == msg.sender, "Buyer mismatch"); // Added buyer verification

        // Signature verifications
        require(
            _verifyUserSignature(
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                order.userSignature
            ),
            "Invalid user signature"
        );

        require(
            _verifyRelayerSignature(
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                order.userSignature,
                order.relayerSignature
            ),
            "Invalid relayer signature"
        );

        _processPurchase(order.roundId, order.gptAmount, order.paymentToken, order.buyer, true);

        nonces[order.buyer]++;
    }

    /**
     * @notice Allows an authorized purchase during the public sale stage using a signature.
     * @param order The order struct containing the purchase details.
     */
    function authorizePurchase(Order calldata order) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PublicSale, "Public sale not active");
        require(order.nonce == nonces[order.buyer], "Invalid nonce");
        require(block.timestamp <= order.expiry, "Signature expired");

        // Verify original user signature
        require(
            _verifyUserSignature(
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                order.userSignature
            ),
            "Invalid user signature"
        );

        // Verify relayer signature
        require(
            _verifyRelayerSignature(
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                order.userSignature,
                order.relayerSignature
            ),
            "Invalid relayer signature"
        );

        // Process the purchase
        _processPurchase(order.roundId, order.gptAmount, order.paymentToken, order.buyer, false);

        nonces[order.buyer]++;
    }

    // === Signature Verification ===
    function _verifyUserSignature(
        uint256 roundId,
        address buyer,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        address paymentToken,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 structHash =
            keccak256(abi.encode(USER_ORDER_TYPEHASH, roundId, buyer, amount, nonce, expiry, paymentToken, chainId));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        return SignatureChecker.isValidSignatureNow(buyer, digest, signature);
    }

    function _verifyRelayerSignature(
        uint256 roundId,
        address buyer,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        address paymentToken,
        bytes memory userSignature,
        bytes memory relayerSignature
    ) internal view returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(
                RELAYER_ORDER_TYPEHASH, roundId, buyer, amount, nonce, expiry, paymentToken, userSignature, chainId
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        require(relayerSignature.length == 65, "Invalid signature length");
        return SignatureChecker.isValidSignatureNow(trustedSigner, digest, relayerSignature);
    }

    // === Price Calculation ===
    function calculatePrice(address paymentToken, uint256 gptAmount) public view returns (uint256 tokenAmount) {
        TokenConfig memory config = acceptedTokens[paymentToken];
        require(config.isAccepted, "Token not accepted");

        (int256 goldPrice, int256 tokenPrice) = PriceCalculator.getLatestPrices(goldPriceFeed, config.priceFeed);

        tokenAmount = PriceCalculator.calculateTokenAmount(
            goldPrice, tokenPrice, gptAmount, config.decimals, TOKENS_PER_TROY_OUNCE
        );
    }

    // === Emergency Functions ===
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        emit Paused(msg.sender, block.timestamp);
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
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
    function recoverERC20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(gptToken), "Cannot recover GPT token");
        require(amount > 0, "Amount must be greater than 0");
        require(ERC20Upgradeable(token).balanceOf(address(this)) >= amount, "Insufficient balance");

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
    function addToWhitelist(address addr) external onlyRole(SALES_MANAGER_ROLE) {
        require(addr != address(0), "Invalid address");

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
    function removeFromWhitelist(address addr) external onlyRole(SALES_MANAGER_ROLE) {
        require(addr != address(0), "Invalid address");
        require(whitelistedAddresses[addr], "Address not whitelisted");

        whitelistedAddresses[addr] = false;
        delete whitelistedAddresses[addr];

        emit AddressRemoved(addr);
    }

    // === Internal Functions ===

    /**
     * @dev Processes the purchase of tokens during a sale round.
     * @param amount The amount of tokens to be purchased.
     * @param paymentToken The address of the token used for payment.
     * @param buyer The address of the buyer.
     *
     * Requirements:
     * - The current round must be active.
     * - The current time must be before the round's end time.
     * - The total tokens sold in the round plus the amount being purchased must not exceed the round's maximum token limit.
     * - The buyer must have a sufficient balance of the payment token.
     *
     * Emits a {TokensPurchased} event.
     */
    function _processPurchase(uint256 roundId, uint256 amount, address paymentToken, address buyer, bool isPresale)
        internal
    {
        // check if the contract is paused
        require(!paused(), "Contract is paused");

        // check if the round is active
        Round storage round = rounds[roundId];
        require(round.isActive, "No active round");
        require(block.timestamp <= round.endTime, "Round ended");
        require(round.tokensSold + amount <= round.maxTokens, "Exceeds round limit");

        uint256 tokenAmount = calculatePrice(paymentToken, amount);

        // console.log("token amount: %s", tokenAmount);

        // Check if the buyer has enough balance
        uint256 userBalance = ERC20Upgradeable(paymentToken).balanceOf(buyer);
        require(userBalance >= tokenAmount, "Insufficient balance");

        // Transfer tokens to the contract
        ERC20Upgradeable(paymentToken).safeTransferFrom(buyer, address(tradingVault), tokenAmount);

        round.tokensSold += amount;
        gptToken.mint(buyer, amount);

        emit TokensPurchased(buyer, amount, tokenAmount, paymentToken, isPresale);
    }

    // === UUPS Upgrade ===
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
