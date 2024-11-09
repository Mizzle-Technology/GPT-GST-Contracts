// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import "../tokens/GoldPackToken.sol";

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

    uint256 public saleAmount;
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => uint256) public nonces;

    bytes32 public constant SALES_MANAGER_ROLE = keccak256("SALES_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcSpent);
    event TrustedSignerUpdated(address indexed newSigner);
    event SalesManagerAdded(address indexed account);
    event SalesManagerRemoved(address indexed account);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

    constructor(address _usdcToken, address _gptToken, address _trustedSigner) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SALES_MANAGER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(SALES_MANAGER_ROLE, ADMIN_ROLE);
        usdcToken = IERC20(_usdcToken);
        gptToken = GoldPackToken(_gptToken);
        currentStage = SaleStage.PreMarketing;
        trustedSigner = _trustedSigner;
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
    function purchaseTokens(uint256 _amount) external {
        require(currentStage == SaleStage.PreSale || currentStage == SaleStage.PublicSale, "Sales not active");
        require(_amount > 0, "Amount must be greater than zero");
        if (currentStage == SaleStage.PreSale) {
            require(whitelistedAddresses[msg.sender], "Not whitelisted");
        }
        uint256 usdcAmount = calculatePrice(_amount);
        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");
        gptToken.mint(msg.sender, _amount);
        emit TokensPurchased(msg.sender, _amount, usdcAmount);
    }

    function calculatePrice(uint256 _amount) internal pure returns (uint256) {
        // Implement price calculation logic
        return _amount * 1e6; // Example: 1 GPT = 1 USDC (assuming USDC has 6 decimals)
    }

    // Authorization function for public sale
    function authorizePurchase(uint256 _amount, uint256 _nonce, bytes memory _signature) external nonReentrant {
        require(currentStage == SaleStage.PublicSale, "Public sale not active");
        require(_amount > 0, "Amount must be greater than zero");
        require(_nonce == nonces[msg.sender], "Invalid nonce");
        require(verifySignature(msg.sender, _amount, _nonce, _signature), "Invalid signature");

        uint256 usdcAmount = calculatePrice(_amount);
        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        gptToken.mint(msg.sender, _amount);
        nonces[msg.sender]++;

        emit TokensPurchased(msg.sender, _amount, usdcAmount);
    }

    function verifySignature(address _buyer, uint256 _amount, uint256 _nonce, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        bytes32 messageHash = keccak256(abi.encode(_buyer, _amount, _nonce));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        return SignatureChecker.isValidSignatureNow(trustedSigner, ethSignedMessageHash, _signature);
    }

    function setTrustedSigner(address _newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedSigner = _newSigner;
        emit TrustedSignerUpdated(_newSigner);
    }
}
