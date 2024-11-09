// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import "../tokens/GoldPackToken.sol";
import "@openzeppelin/utils/cryptography/ECDSA.sol";

/**
 * @title SalesContract
 * @notice Manages GPT token sales with role-based access control
 * @dev ADMIN_ROLE: Withdrawals and emergency functions
 *      SALES_MANAGER_ROLE: Sales and round management
 */
contract SalesContract is AccessControl, ReentrancyGuard {
    // Use SafeERC20 for all IERC20 tokens
    using SafeERC20 for IERC20;

    // === State Variables ===

    // Enumerations
    enum SaleStage {
        PreMarketing,
        Whitelisting,
        PreSale,
        PublicSale
    }

    // Contract roles
    bytes32 public constant SALES_MANAGER_ROLE = keccak256("SALES_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Tokens and price feed
    IERC20 public usdcToken;
    GoldPackToken public gptToken;
    AggregatorV3Interface internal goldPriceFeed;

    // Mapping of accepted tokens to their aggregator addresses (for price feeds)
    mapping(address => AggregatorV3Interface) public acceptedTokens;

    // Sales management
    SaleStage public currentStage;
    bool public paused;
    uint256 public maxPurchaseAmount;
    uint256 public totalTokensSold;

    // Trusted signer for authorization
    address public trustedSigner;

    // Rounds management
    struct Round {
        uint256 maxTokens;
        uint256 tokensSold;
        bool isActive;
        uint256 startTime;
        uint256 endTime;
    }

    uint256 public currentRoundId;
    mapping(uint256 => Round) public rounds;

    // User data
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => uint256) public nonces;

    // Timelock management
    uint256 public constant TIMELOCK_DURATION = 24 hours;
    uint256 public constant WITHDRAWAL_THRESHOLD = 100_000e6; // 100k USDC
    mapping(bytes32 => uint256) public timelockExpiries;

    // EIP-712 domain separator and type hashes
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant PURCHASE_TYPE_HASH =
        keccak256("Purchase(address buyer,uint256 amount,uint256 nonce,uint256 expiry,uint256 chainId)");
    bytes32 private immutable DOMAIN_SEPARATOR;

    // Pause reason
    string public pauseReason;

    // Events
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 tokenSpent, address indexed paymentToken);
    event RoundCreated(uint256 indexed roundId, uint256 maxTokens, uint256 startTime, uint256 endTime);
    event RoundActivated(uint256 indexed roundId);
    event RoundDeactivated(uint256 indexed roundId);
    event WithdrawalQueued(uint256 amount);
    event WithdrawalExecuted(uint256 amount);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event SalesManagerAdded(address indexed account);
    event SalesManagerRemoved(address indexed account);

    // === Modifiers ===

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    // === Constructor ===

    /**
     * @notice Contract constructor
     * @param _usdcToken USDC token address
     * @param _gptToken GPT token address
     * @param _goldPriceFeed Chainlink gold price feed address
     * @param _trustedSigner Address that signs purchase authorizations
     */
    constructor(address _usdcToken, address _gptToken, address _goldPriceFeed, address _trustedSigner) {
        // Validate addresses
        require(_usdcToken != address(0), "Invalid USDC address");
        require(_gptToken != address(0), "Invalid GPT address");
        require(_goldPriceFeed != address(0), "Invalid price feed address");
        require(_trustedSigner != address(0), "Invalid signer address");

        // Initialize roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SALES_MANAGER_ROLE, ADMIN_ROLE);

        // Initialize state variables
        usdcToken = IERC20(_usdcToken);
        gptToken = GoldPackToken(_gptToken);
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
        trustedSigner = _trustedSigner;
        currentStage = SaleStage.PreMarketing;

        // Compute the domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, keccak256(bytes("GPTSales")), keccak256(bytes("1")), block.chainid, address(this)
            )
        );
    }

    // === External Functions ===

    // Role Management
    function addSalesManager(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(SALES_MANAGER_ROLE, account);
        emit SalesManagerAdded(account);
    }

    function removeSalesManager(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(SALES_MANAGER_ROLE, account);
        emit SalesManagerRemoved(account);
    }

    // Sales Manager Functions
    function setSaleStage(SaleStage _stage) external onlyRole(SALES_MANAGER_ROLE) {
        currentStage = _stage;
    }

    // Pause Management
    function pause(string memory reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!paused, "Contract already paused");
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(paused, "Contract not paused");
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    function createRound(uint256 _maxTokens, uint256 _startTime, uint256 _endTime)
        external
        onlyRole(SALES_MANAGER_ROLE)
    {
        require(_startTime > block.timestamp, "Start time must be in future");
        require(_endTime > _startTime, "End time must be after start time");

        currentRoundId++;
        rounds[currentRoundId] =
            Round({maxTokens: _maxTokens, tokensSold: 0, isActive: false, startTime: _startTime, endTime: _endTime});

        emit RoundCreated(currentRoundId, _maxTokens, _startTime, _endTime);
    }

    function activateRound(uint256 _roundId) external onlyRole(SALES_MANAGER_ROLE) {
        require(_roundId <= currentRoundId, "Round does not exist");
        Round storage round = rounds[_roundId];
        require(!round.isActive, "Round already active");
        require(block.timestamp >= round.startTime, "Round not started");
        require(block.timestamp <= round.endTime, "Round ended");

        round.isActive = true;
        emit RoundActivated(_roundId);
    }

    // Purchase Functions
    /**
     * @notice Allows a whitelisted address to make a purchase during the presale stage.
     * @dev This function can only be called when the contract is not paused and the current stage is PreSale.
     * @param _amount The amount of tokens to purchase.
     * @param _paymentToken The address of the payment token.
     * require The current stage must be PreSale.
     * require The caller must be a whitelisted address.
     */
    function presalePurchase(uint256 _amount, address _paymentToken) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PreSale, "Presale not active");
        require(whitelistedAddresses[msg.sender], "Not whitelisted");
        _processPurchase(_amount, _paymentToken);
    }

    /**
     * @notice Allows an authorized purchase during the public sale stage using a signature.
     * @dev This function can only be called when the contract is not paused and the current stage is PublicSale.
     * @param _amount The amount of tokens to purchase.
     * @param _nonce A unique number to prevent replay attacks.
     * @param _expiry The timestamp until which the signature is valid.
     * @param _signature The signature to verify the purchase authorization.
     * @param _paymentToken The address of the payment token.
     * require The current stage must be PublicSale.
     * require The provided nonce must match the stored nonce for the caller.
     * require The current timestamp must be less than or equal to the provided expiry timestamp.
     * require The provided signature must be valid.
     */
    function authorizePurchase(
        uint256 _amount,
        uint256 _nonce,
        uint256 _expiry,
        bytes memory _signature,
        address _paymentToken
    ) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PublicSale, "Public sale not active");
        require(_nonce == nonces[msg.sender], "Invalid nonce");
        require(block.timestamp <= _expiry, "Signature expired");
        require(verifySignature(msg.sender, _amount, _nonce, _expiry, _signature), "Invalid signature");

        _processPurchase(_amount, _paymentToken);
        nonces[msg.sender]++;
    }

    // Admin Functions
    /**
     * @notice Queues a withdrawal request that exceeds the defined threshold.
     * @dev Only callable by accounts with the ADMIN_ROLE.
     * @param amount The amount to be withdrawn.
     * Requirements:
     * - `amount` must be greater than `WITHDRAWAL_THRESHOLD`.
     * - The function will hash the withdrawal request and set a timelock expiry.
     * Emits a {WithdrawalQueued} event.
     */
    function queueWithdrawal(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(amount > WITHDRAWAL_THRESHOLD, "Small withdrawals don't need timelock");
        bytes32 hash = keccak256(abi.encode("withdraw", amount));
        timelockExpiries[hash] = block.timestamp + TIMELOCK_DURATION;
        emit WithdrawalQueued(amount);
    }

    /**
     * @notice Executes a withdrawal of the specified amount of USDC tokens.
     * @dev This function can only be called by an account with the ADMIN_ROLE.
     *      The withdrawal must be queued and the timelock must have expired.
     * @param amount The amount of USDC tokens to withdraw.
     * require The withdrawal must have been queued.
     * require The timelock must have expired.
     * require The contract must have sufficient USDC balance.
     * require The USDC transfer must succeed.
     * emit WithdrawalExecuted Emitted when the withdrawal is successfully executed.
     */
    function executeWithdrawal(uint256 amount) external onlyRole(ADMIN_ROLE) {
        bytes32 hash = keccak256(abi.encode("withdraw", amount));
        require(timelockExpiries[hash] != 0, "Withdrawal not queued");
        require(block.timestamp >= timelockExpiries[hash], "Timelock not expired");
        require(amount <= usdcToken.balanceOf(address(this)), "Insufficient balance");

        delete timelockExpiries[hash];
        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
        emit WithdrawalExecuted(amount);
    }

    /**
     * @notice Withdraws a small amount of USDC from the contract.
     * @dev Only callable by accounts with the ADMIN_ROLE.
     * @param amount The amount of USDC to withdraw.
     * Requirements:
     * - `amount` must be greater than 0 and less than or equal to WITHDRAWAL_THRESHOLD.
     * - `amount` must be less than or equal to the contract's USDC balance.
     * - The USDC transfer must succeed.
     * Reverts with:
     * - "Use queued withdrawal" if `amount` is not within the valid range.
     * - "Insufficient balance" if the contract's USDC balance is insufficient.
     * - "Transfer failed" if the USDC transfer fails.
     */
    function withdrawUSDC(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(amount > 0 && amount <= WITHDRAWAL_THRESHOLD, "Use queued withdrawal");
        require(amount <= usdcToken.balanceOf(address(this)), "Insufficient balance");
        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
    }

    /**
     * @notice Add a new token to the list of accepted payment tokens.
     * @dev Only callable by accounts with the ADMIN_ROLE.
     * @param tokenAddress The address of the ERC20 token contract.
     * @param priceFeedAddress The address of the Chainlink price feed contract for the token.
     */
    function addAcceptedToken(address tokenAddress, address priceFeedAddress) external onlyRole(ADMIN_ROLE) {
        require(tokenAddress != address(0), "Invalid token address");
        require(priceFeedAddress != address(0), "Invalid price feed address");
        acceptedTokens[tokenAddress] = AggregatorV3Interface(priceFeedAddress);
    }

    /**
     * @notice Remove a token from the list of accepted payment tokens.
     * @dev Only callable by accounts with the ADMIN_ROLE.
     * @param tokenAddress The address of the ERC20 token contract.
     */
    function removeAcceptedToken(address tokenAddress) external onlyRole(ADMIN_ROLE) {
        require(acceptedTokens[tokenAddress] != AggregatorV3Interface(address(0)), "Token not accepted");
        delete acceptedTokens[tokenAddress];
    }

    // === Internal Functions ===

    /**
     * @dev Processes the purchase of GPT tokens.
     * @param _amount The amount of tokens to purchase.
     * @param _paymentToken The address of the payment token.
     */
    function _processPurchase(uint256 _amount, address _paymentToken) internal {
        require(_amount > 0, "Amount must be greater than zero");
        require(_amount <= maxPurchaseAmount, "Exceeds maximum purchase amount");
        require(acceptedTokens[_paymentToken] != AggregatorV3Interface(address(0)), "Payment token not accepted");

        Round storage round = rounds[currentRoundId];
        require(round.isActive, "No active round");
        require(block.timestamp <= round.endTime, "Round ended");
        require(round.tokensSold + _amount <= round.maxTokens, "Exceeds round limit");

        uint256 tokenAmount = calculatePrice(_amount, _paymentToken);
        IERC20 paymentToken = IERC20(_paymentToken);

        // Use SafeERC20 to handle tokens that don't return a boolean
        paymentToken.safeTransferFrom(msg.sender, address(this), tokenAmount);

        round.tokensSold += _amount;
        totalTokensSold += _amount;
        gptToken.mint(msg.sender, _amount);

        emit TokensPurchased(msg.sender, _amount, tokenAmount, _paymentToken);
    }

    /**
     * @dev Calculates the USDC price for a given amount of GPT tokens based on the gold price.
     * @param _amount The amount of GPT tokens to calculate the price for.
     * @param _paymentToken The address of the payment token.
     * @return totalPriceInToken The total amount of the payment token required for the purchase.
     */
    function calculatePrice(uint256 _amount, address _paymentToken) internal view returns (uint256) {
        AggregatorV3Interface tokenPriceFeed = acceptedTokens[_paymentToken];
        require(address(tokenPriceFeed) != address(0), "No price feed for token");

        // Fetch the latest gold price in USD
        (, int256 goldPrice,, uint256 goldUpdatedAt,) = goldPriceFeed.latestRoundData();
        require(block.timestamp - goldUpdatedAt <= 1 hours, "Stale gold price");
        require(goldPrice > 0, "Invalid gold price");
        uint8 goldDecimals = goldPriceFeed.decimals();
        uint256 goldPriceUSD = uint256(goldPrice);

        // Fetch the latest payment token price in USD
        (, int256 tokenPrice,, uint256 tokenUpdatedAt,) = tokenPriceFeed.latestRoundData();
        require(block.timestamp - tokenUpdatedAt <= 1 hours, "Stale token price");
        require(tokenPrice > 0, "Invalid token price");
        uint8 tokenDecimals = tokenPriceFeed.decimals();
        uint256 tokenPriceUSD = uint256(tokenPrice);

        // Calculate the price of GPT tokens in terms of the payment token
        uint256 goldPriceAdjusted = goldPriceUSD * (10 ** tokenDecimals) / (10 ** goldDecimals);
        uint256 totalPriceInToken = (_amount * goldPriceAdjusted) / tokenPriceUSD;

        // Adjust for token decimals
        return totalPriceInToken;
    }

    /**
     * @dev Verifies the signature for an authorized purchase during the public sale.
     * @param _buyer The address of the buyer.
     * @param _amount The amount of GPT tokens to purchase.
     * @param _nonce The buyer's current nonce.
     * @param _expiry The expiration timestamp of the signature.
     * @param _signature The signature provided by the trusted signer.
     * @return isValid True if the signature is valid, false otherwise.
     */
    function verifySignature(address _buyer, uint256 _amount, uint256 _nonce, uint256 _expiry, bytes memory _signature)
        internal
        view
        returns (bool isValid)
    {
        // Ensure the signature has not expired
        require(block.timestamp <= _expiry, "Signature expired");

        // Hash the purchase data according to EIP-712
        bytes32 structHash = keccak256(abi.encode(PURCHASE_TYPE_HASH, _buyer, _amount, _nonce, _expiry, block.chainid));

        // Compute the digest to sign
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Recover the signer from the signature
        address recoveredSigner = ECDSA.recover(digest, _signature);

        // Check if the recovered signer is the trusted signer
        isValid = (recoveredSigner == trustedSigner);
    }
}
