// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/sales/ISalesContract.sol";
import "../src/sales/SalesContract.sol";
import "../src/vault/BurnVault.sol";
import "../src/vault/TradingVault.sol";
import "./Mocks.sol";

contract SalesContractPresaleTest is Test {
    using ECDSA for bytes32;

    // Define constants at the contract level
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant GPT_DECIMALS = 6;

    GoldPackToken private gptToken;
    SalesContract private salesContract;
    MockERC20 private usdc;
    MockAggregator private goldPriceFeed;
    MockAggregator private usdcPriceFeed;
    TradingVault private tradingVault;

    address private user;
    address private relayer;
    address private admin = address(1);
    address private sales = address(2);
    address private user2 = address(3);
    address private safeWallet = address(4);
    uint256 private userPrivateKey;
    uint256 private relayerPrivateKey;

    ISalesContract.Order private order;

    function setUp() public {
        // Deploy mock tokens and price feeds
        usdc = new MockERC20();
        usdc.initialize("USDC", "USDC", 6);

        goldPriceFeed = new MockAggregator();
        usdcPriceFeed = new MockAggregator();

        // Set realistic prices with 8 decimals
        goldPriceFeed.setPrice(2000 * 10 ** 8); // $2000/oz with 8 decimals
        usdcPriceFeed.setPrice(1 * 10 ** 8); // $1/USDC with 8 decimals

        // Generate private keys
        userPrivateKey = uint256(keccak256("user private key"));
        relayerPrivateKey = uint256(keccak256("relayer private key"));

        // Derive the associated addresses
        user = vm.addr(userPrivateKey);
        relayer = vm.addr(relayerPrivateKey);

        // Deploy BurnVault
        BurnVault burnVault = new BurnVault();
        burnVault.initialize();

        // Deploy GoldPackToken and SalesContract
        vm.startPrank(admin);
        gptToken = new GoldPackToken();
        gptToken.initialize(address(burnVault));

        // Deploy TradingVault
        tradingVault = new TradingVault();
        tradingVault.initialize(safeWallet);

        // Note: SalesContract constructor grants DEFAULT_ADMIN_ROLE to msg.sender
        salesContract = new SalesContract();
        salesContract.initialize(address(gptToken), address(goldPriceFeed), relayer, address(tradingVault));

        // Grant SALES_ROLE to SalesContract
        gptToken.grantRole(gptToken.SALES_ROLE(), address(salesContract));
        vm.stopPrank();

        // Set up token address in BurnVault
        burnVault.setToken(ERC20Upgradeable(address(gptToken)));

        // Setup roles and configuration
        vm.startPrank(admin);
        salesContract.grantRole(salesContract.SALES_MANAGER_ROLE(), sales);
        salesContract.addAcceptedToken(address(usdc), address(usdcPriceFeed), 6);
        vm.stopPrank();

        vm.startPrank(sales);
        salesContract.addToWhitelist(user);
        salesContract.setSaleStage(ISalesContract.SaleStage.PublicSale);
        vm.stopPrank();

        // Set up the order object

        order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });
    }

    function testPresaleNotActive() public {
        vm.prank(user);
        vm.expectRevert("Presale not active");
        salesContract.preSalePurchase(order);
    }

    function testNotWhitelisted() public {
        // Set up the order object
        vm.startPrank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PreSale);
        salesContract.removeFromWhitelist(user);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        salesContract.preSalePurchase(order);
    }

    function testBuyerMismatch() public {
        // Set up the order object
        vm.startPrank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PreSale);
        salesContract.addToWhitelist(user2);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("Buyer mismatch");
        salesContract.preSalePurchase(order);
    }

    function testInvalidUserSignature() public {
        vm.prank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PreSale);

        // Generate a valid user signature and then modify it to be invalid
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        bytes memory validSignature = abi.encodePacked(r, s, v);
        bytes memory invalidSignature = validSignature;
        invalidSignature[0] = 0x00; // Modify the signature to make it invalid
        order.userSignature = invalidSignature;

        // Generate relayer signature
        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.prank(user);
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)

        vm.prank(user);
        vm.expectRevert("Invalid user signature");
        salesContract.preSalePurchase(order);
    }

    function testFailInvalidRelayerSignature() public {
        vm.prank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PreSale);

        vm.prank(user);
        salesContract.preSalePurchase(order);
    }

    function testSuccessfulPurchase() public {
        vm.prank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PreSale);

        usdc.mint(user, 2000 * 10 ** 6); // Mint 2000 USDC to user

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the first round
        vm.stopPrank();

        // Generate user signature
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        order.userSignature = abi.encodePacked(r, s, v);

        // Generate relayer signature
        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

        vm.prank(user);
        salesContract.preSalePurchase(order);

        // Add assertions to verify the state changes
        // Verify results
        assertEq(gptToken.balanceOf(user), 10000_000000);
        assertEq(usdc.balanceOf(user), 0); // Should be 0 if exact
        assertEq(salesContract.nonces(user), 1);
    }

    function _getUserDigest(ISalesContract.Order memory userOrder) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                salesContract.USER_ORDER_TYPEHASH(),
                userOrder.roundId,
                userOrder.buyer,
                userOrder.gptAmount,
                userOrder.nonce,
                userOrder.expiry,
                userOrder.paymentToken,
                block.chainid
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", salesContract.DOMAIN_SEPARATOR(), structHash));
    }

    function _getRelayerDigest(ISalesContract.Order memory relayerOrder) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                salesContract.RELAYER_ORDER_TYPEHASH(),
                relayerOrder.roundId,
                relayerOrder.buyer,
                relayerOrder.gptAmount,
                relayerOrder.nonce,
                relayerOrder.expiry,
                relayerOrder.paymentToken,
                relayerOrder.userSignature,
                block.chainid
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", salesContract.DOMAIN_SEPARATOR(), structHash));
    }
}
