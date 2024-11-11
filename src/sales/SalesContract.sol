// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/utils/Pausable.sol";
import "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "../tokens/GoldPackToken.sol";
import "../libs/PriceCalculator.sol";

/**
 * @title SalesContract
 * @notice Manages GPT token sales with role-based access control
 * @dev ADMIN_ROLE: Withdrawals and emergency functions
 *      SALES_MANAGER_ROLE: Sales and round management
 *      Data Feeds for Testnet: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
 *      Data Feeds for Mainnet: https://data.chain.link/feeds
 */
contract SalesContract is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using PriceCalculator for *;

    // === Constants ===
    uint256 public constant TOKENS_PER_TROY_OUNCE = 10_000_000000; // 10,000 GPT tokens with 6 decimals
    uint256 public constant TIMELOCK_DURATION = 24 hours;
    uint256 public constant WITHDRAWAL_THRESHOLD = 100_000e6; // 100k USDC
    /// @dev Maximum time allowed between price updates
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SALES_MANAGER_ROLE = keccak256("SALES_MANAGER_ROLE");
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant USER_ORDER_TYPEHASH = keccak256(
        "Order(address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,uint256 chainId)"
    );
    bytes32 public constant RELAYER_ORDER_TYPEHASH = keccak256(
        "RelayerOrder(address buyer,uint256 gptAmount,uint256 nonce,uint256 expiry,address paymentToken,bytes userSignature,uint256 chainId)"
    );
    bytes32 public immutable DOMAIN_SEPARATOR;

    // === State Variables ===
    uint256 public maxPurchaseAmount;
    uint256 public totalTokensSold;
    uint256 public currentRoundId;
    uint256 private immutable chainId;
    string public pauseReason;
    address public trustedSigner;
    GoldPackToken public gptToken;
    AggregatorV3Interface internal goldPriceFeed;
    SaleStage public currentStage;

    mapping(address => TokenConfig) public acceptedTokens;
    mapping(uint256 => Round) public rounds;
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => uint256) public timelockExpiries;
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;

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
        address buyer;
        uint256 gptAmount;
        uint256 nonce;
        uint256 expiry;
        address paymentToken;
        bytes userSignature;
        bytes relayerSignature;
    }

    // withdrawal request struct
    struct WithdrawalRequest {
        address token;
        uint256 amount;
        uint256 expiry;
        bool executed;
        bool cancelled;
    }

    // === Events ===
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 tokenSpent, address indexed paymentToken);
    event RoundCreated(uint256 indexed roundId, uint256 maxTokens, uint256 startTime, uint256 endTime);
    event RoundActivated(uint256 indexed roundId);
    event RoundDeactivated(uint256 indexed roundId);
    event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event PriceAgeUpdated(uint256 oldAge, uint256 newAge);
    event Paused(address indexed pauser, uint256 timestamp);
    event Unpaused(address indexed unpauser, uint256 timestamp);
    event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);
    event ETHRecovered(uint256 amount, address indexed recipient);
    event WithdrawalQueued(bytes32 indexed withdrawalId, uint256 amount, uint256 timelockExpiry);
    event WithdrawalExecuted(bytes32 indexed withdrawalId, uint256 amount);
    event WithdrawalQueued(
        bytes32 indexed withdrawalId,
        address indexed token,
        uint256 amount,
        uint256 timelockExpiry,
        address indexed initiator
    );

    event WithdrawalExecuted(
        bytes32 indexed withdrawalId, address indexed token, uint256 amount, address indexed executor
    );
    event WithdrawalCancelled(
        bytes32 indexed withdrawalId, address indexed token, uint256 amount, address indexed cancelledBy
    );

    // === Constructor ===
    /**
     * @notice Contract constructor
     * @param _gptToken GPT token address
     * @param _goldPriceFeed Chainlink gold price feed address
     * @param _trustedSigner Address that signs purchase authorizations
     */
    constructor(address _gptToken, address _goldPriceFeed, address _trustedSigner) {
        require(_gptToken != address(0), "Invalid GPT address");
        require(_goldPriceFeed != address(0), "Invalid price feed address");
        require(_trustedSigner != address(0), "Invalid signer address");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SALES_MANAGER_ROLE, ADMIN_ROLE);

        gptToken = GoldPackToken(_gptToken);
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

    // === Round Management ===
    /**
     * @notice Creates a new sale round
     * @param maxTokens Maximum number of tokens available in the round
     * @param startTime Start time of the round
     * @param endTime End time of the round
     */
    function createRound(uint256 maxTokens, uint256 startTime, uint256 endTime) external onlyRole(SALES_MANAGER_ROLE) {
        require(startTime < endTime, "Invalid round time");
        rounds[currentRoundId] =
            Round({maxTokens: maxTokens, tokensSold: 0, isActive: false, startTime: startTime, endTime: endTime});
        emit RoundCreated(currentRoundId, maxTokens, startTime, endTime);
        currentRoundId++;
    }

    /**
     * @notice Activates a sale round
     * @param roundId ID of the round to activate
     */
    function activateRound(uint256 roundId) external onlyRole(SALES_MANAGER_ROLE) {
        require(roundId < currentRoundId, "Round does not exist");
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
        require(roundId < currentRoundId, "Round does not exist");
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
    function setSaleStage(SaleStage _stage) external onlyRole(ADMIN_ROLE) {
        currentStage = _stage;
    }

    // === Purchase Functions ===
    /**
     * @notice Allows a whitelisted address to make a purchase during the presale stage.
     * @param amount The amount of tokens to purchase.
     * @param paymentToken The address of the payment token.
     */
    function presalePurchase(uint256 amount, address paymentToken) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PreSale, "Presale not active");
        require(whitelistedAddresses[msg.sender], "Not whitelisted");
        _processPurchase(amount, paymentToken);
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
                order.buyer, order.gptAmount, order.nonce, order.expiry, order.paymentToken, order.userSignature
            ),
            "Invalid user signature"
        );

        // Verify relayer signature
        require(
            _verifyRelayerSignature(
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

        uint256 tokenAmount = calculatePrice(order.paymentToken, order.gptAmount);

        IERC20(order.paymentToken).transferFrom(order.buyer, address(this), tokenAmount);

        gptToken.mint(order.buyer, order.gptAmount);

        nonces[order.buyer]++;

        emit TokensPurchased(order.buyer, order.gptAmount, tokenAmount, order.paymentToken);
    }

    // === Withdrawal Functions ===
    /**
     * @notice Queues a withdrawal request
     * @param amount The amount to withdraw
     * @param token The address of the token to withdraw
     * @dev Only admin can call
     */
    function queueWithdrawal(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        require(acceptedTokens[token].isAccepted, "Token not accepted");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient balance");

        if (amount >= WITHDRAWAL_THRESHOLD) {
            // Large withdrawals need timelock
            bytes32 withdrawalId = keccak256(abi.encodePacked(block.timestamp, msg.sender, token, amount));

            withdrawalRequests[withdrawalId] = WithdrawalRequest({
                token: token,
                amount: amount,
                expiry: block.timestamp + TIMELOCK_DURATION,
                executed: false,
                cancelled: false
            });

            emit WithdrawalQueued(withdrawalId, token, amount, block.timestamp + TIMELOCK_DURATION, msg.sender);
        } else {
            // Small withdrawals execute immediately
            IERC20(token).safeTransfer(msg.sender, amount);
            emit WithdrawalExecuted(
                keccak256(abi.encodePacked(block.timestamp, msg.sender, token, amount)), token, amount, msg.sender
            );
        }
    }

    /**
     * @notice Executes a queued withdrawal request
     * @param withdrawalId The ID of the withdrawal request
     * Requirements:
     * - Only admin can call
     * - Withdrawal must be queued and not executed
     * - Timelock must have expired
     */
    function executeWithdrawal(bytes32 withdrawalId) external onlyRole(ADMIN_ROLE) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        require(request.expiry != 0, "Withdrawal not queued");
        require(!request.executed, "Withdrawal already executed");
        require(!request.cancelled, "Withdrawal already cancelled");
        require(block.timestamp >= request.expiry, "Timelock not expired");
        require(IERC20(request.token).balanceOf(address(this)) >= request.amount, "Insufficient balance");

        request.executed = true;
        IERC20(request.token).safeTransfer(msg.sender, request.amount);

        emit WithdrawalExecuted(withdrawalId, request.token, request.amount, msg.sender);
    }

    /**
     * @notice Cancels a queued withdrawal request
     * @param withdrawalId The ID of the withdrawal to cancel
     * Requirements:
     * - Only admin can call
     * - Withdrawal must be queued
     * - Withdrawal must not be executed
     * - Withdrawal must not be cancelled
     */
    function cancelWithdrawal(bytes32 withdrawalId) external onlyRole(ADMIN_ROLE) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        require(request.expiry != 0, "Withdrawal not queued");
        require(!request.executed, "Withdrawal already executed");
        require(!request.cancelled, "Withdrawal already cancelled");
        require(block.timestamp < request.expiry, "Withdrawal period expired");

        request.cancelled = true;
        emit WithdrawalCancelled(withdrawalId, request.token, request.amount, msg.sender);
    }

    // === Signature Verification ===
    function _verifyUserSignature(
        address buyer,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        address paymentToken,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 structHash =
            keccak256(abi.encode(USER_ORDER_TYPEHASH, buyer, amount, nonce, expiry, paymentToken, chainId));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        address recoveredSigner = ECDSA.recover(digest, signature);
        require(recoveredSigner != address(0), "Invalid signature");
        return recoveredSigner == buyer;
    }

    function _verifyRelayerSignature(
        address buyer,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        address paymentToken,
        bytes memory userSignature,
        bytes memory relayerSignature
    ) internal view returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(RELAYER_ORDER_TYPEHASH, buyer, amount, nonce, expiry, paymentToken, userSignature, chainId)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        require(relayerSignature.length == 65, "Invalid signature length");
        address recoveredSigner = ECDSA.recover(digest, relayerSignature);
        require(recoveredSigner != address(0), "Invalid signature");
        return recoveredSigner == trustedSigner;
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
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient balance");

        IERC20(token).safeTransfer(msg.sender, amount);
        emit TokenRecovered(token, amount, msg.sender);
    }

    // === Internal Functions ===
    function _processPurchase(uint256 amount, address paymentToken) internal {
        Round storage round = rounds[currentRoundId];
        require(round.isActive, "No active round");
        require(block.timestamp <= round.endTime, "Round ended");
        require(round.tokensSold + amount <= round.maxTokens, "Exceeds round limit");

        uint256 tokenAmount = calculatePrice(paymentToken, amount);
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        round.tokensSold += amount;
        gptToken.mint(msg.sender, amount);

        emit TokensPurchased(msg.sender, amount, tokenAmount, paymentToken);
    }
}
