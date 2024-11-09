// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import "../tokens/GoldPackToken.sol";
import "@openzeppelin/utils/cryptography/ECDSA.sol";

contract SalesContract is AccessControl, ReentrancyGuard {
    enum SaleStage {
        PreMarketing,
        Whitelisting,
        PreSale,
        PublicSale
    }

    SaleStage public currentStage;

    IERC20 public usdcToken;
    GoldPackToken public gptToken;
    address public trustedSigner;
    AggregatorV3Interface internal goldPriceFeed;

    uint256 public saleAmount;
    uint256 public maxPurchaseAmount;
    uint256 public maxTokensForSale;
    uint256 public totalTokensSold;
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => uint256) public nonces;

    bytes32 public constant SALES_MANAGER_ROLE = keccak256("SALES_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bool public paused;

    // Domain Separator for EIP-712
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant PURCHASE_TYPE_HASH =
        keccak256("Purchase(address buyer,uint256 amount,uint256 nonce,uint256 expiry)");
    bytes32 private immutable DOMAIN_SEPARATOR;

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcSpent);
    event TrustedSignerUpdated(address indexed newSigner);
    event SalesManagerAdded(address indexed account);
    event SalesManagerRemoved(address indexed account);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);
    event SaleStageUpdated(SaleStage newStage);
    event MaxPurchaseAmountUpdated(uint256 newAmount);
    event Paused(address account);
    event EmergencyWithdraw(address account, uint256 amount);
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);

    constructor(address _usdcToken, address _gptToken, address _goldPriceFeed, address _trustedSigner) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SALES_MANAGER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SALES_MANAGER_ROLE, ADMIN_ROLE);
        usdcToken = IERC20(_usdcToken);
        gptToken = GoldPackToken(_gptToken);
        currentStage = SaleStage.PreMarketing;
        trustedSigner = _trustedSigner;
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, keccak256(bytes("GPTSales")), keccak256(bytes("1")), block.chainid, address(this)
            )
        );
    }

    // Role management functions

    // Functions to manage SALES_MANAGER_ROLE
    function addSalesManager(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(SALES_MANAGER_ROLE, account);
        emit SalesManagerAdded(account);
    }

    function removeSalesManager(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(SALES_MANAGER_ROLE, account);
        emit SalesManagerRemoved(account);
    }

    // Functions to manage ADMIN_ROLE
    function addAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(ADMIN_ROLE, account);
        emit AdminAdded(account);
    }

    function removeAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(ADMIN_ROLE, account);
        emit AdminRemoved(account);
    }

    // If an account wants to renounce its roles
    function renounceMyRoles() external {
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        renounceRole(ADMIN_ROLE, msg.sender);
        renounceRole(SALES_MANAGER_ROLE, msg.sender);
    }

    // Sales manager functions
    function setSaleStage(SaleStage _stage) external onlyRole(SALES_MANAGER_ROLE) {
        currentStage = _stage;
    }

    function setSaleAmount(uint256 _amount) external onlyRole(SALES_MANAGER_ROLE) {
        saleAmount = _amount;
    }

    function addWhitelistedAddress(address _user) external onlyRole(SALES_MANAGER_ROLE) {
        whitelistedAddresses[_user] = true;
    }

    function removeWhitelistedAddress(address _user) external onlyRole(SALES_MANAGER_ROLE) {
        whitelistedAddresses[_user] = false;
    }

    // Purchase functions
    // For presale whitelisted users only
    function presalePurchase(uint256 _amount) external nonReentrant whenNotPaused {
        require(currentStage == SaleStage.PreSale, "Presale not active");
        require(whitelistedAddresses[msg.sender], "Not whitelisted");
        require(_amount > 0, "Amount must be greater than zero");
        require(_amount <= maxPurchaseAmount, "Exceeds maximum purchase amount");

        uint256 usdcAmount = calculatePrice(_amount);
        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        require(totalTokensSold + _amount <= maxTokensForSale, "Exceeds available supply");
        totalTokensSold += _amount;

        gptToken.mint(msg.sender, _amount);
        emit TokensPurchased(msg.sender, _amount, usdcAmount);
    }

    function calculatePrice(uint256 _amount) internal view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = goldPriceFeed.latestRoundData();
        require(block.timestamp - updatedAt <= 1 hours, "Stale price");
        require(price > 0, "Invalid gold price");

        uint8 decimals = goldPriceFeed.decimals();
        uint256 goldPriceUSD = uint256(price);

        // Safe math operations (Solidity ^0.8.0 has built-in overflow checking)
        uint256 adjustedGoldPrice = goldPriceUSD * 1e6 / (10 ** decimals);
        uint256 totalPriceUSDC = (_amount * adjustedGoldPrice) / 10000;

        return totalPriceUSDC;
    }

    // Authorization function for public sale
    function authorizePurchase(uint256 _amount, uint256 _nonce, uint256 _expiry, bytes memory _signature)
        external
        nonReentrant
        whenNotPaused
    {
        require(currentStage == SaleStage.PublicSale, "Public sale not active");
        require(_amount > 0, "Amount must be greater than zero");
        require(_amount <= maxPurchaseAmount, "Exceeds maximum purchase amount");
        require(_nonce == nonces[msg.sender], "Invalid nonce");
        require(block.timestamp <= _expiry, "Signature expired");
        require(verifySignature(msg.sender, _amount, _nonce, _expiry, _signature), "Invalid signature");

        uint256 usdcAmount = calculatePrice(_amount);
        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        require(totalTokensSold + _amount <= maxTokensForSale, "Exceeds available supply");
        totalTokensSold += _amount;

        gptToken.mint(msg.sender, _amount);
        nonces[msg.sender]++;

        emit TokensPurchased(msg.sender, _amount, usdcAmount);
    }

    /// @notice Verifies the signature for authorized purchases
    /// @param _buyer Address of the buyer
    /// @param _amount Amount of tokens to purchase
    /// @param _nonce Current nonce of the buyer
    /// @param _expiry Expiration timestamp of the signature
    /// @param _signature Signature from trusted signer
    /// @return bool Whether the signature is valid
    function verifySignature(address _buyer, uint256 _amount, uint256 _nonce, uint256 _expiry, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(PURCHASE_TYPE_HASH, _buyer, _amount, _nonce, _expiry));

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        address recoveredSigner = ECDSA.recover(hash, _signature);
        return recoveredSigner == trustedSigner;
    }

    function setTrustedSigner(address _newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedSigner = _newSigner;
        emit TrustedSignerUpdated(_newSigner);
    }

    function withdrawUSDC(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
    }

    // Add pause functionality
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    // Add emergency withdrawal
    function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = usdcToken.balanceOf(address(this));
        require(usdcToken.transfer(msg.sender, balance), "Transfer failed");
        emit EmergencyWithdraw(msg.sender, balance);
    }

    function recoverERC20(address tokenAddress, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress != address(usdcToken), "Cannot recover USDC");
        require(IERC20(tokenAddress).transfer(msg.sender, amount), "Transfer failed");
        emit ERC20Recovered(tokenAddress, msg.sender, amount);
    }
}
