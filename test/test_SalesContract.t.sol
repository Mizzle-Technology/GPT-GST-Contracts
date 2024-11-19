// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/sales/SalesContract.sol";
import "../src/sales/ISalesContract.sol";
import "../src/vault/BurnVault.sol";
import "../src/vault/TradingVault.sol";
import "./Mocks.sol";
import "forge-std/console.sol";

contract SalesContractTest is Test {
    // Define constants at the contract level
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant GPT_DECIMALS = 6;

    GoldPackToken private gptToken;
    SalesContract private salesContract;
    TradingVault private tradingVault;
    BurnVault private burnVault;
    MockERC20 private usdc;
    MockAggregator private goldPriceFeed;
    MockAggregator private usdcPriceFeed;

    address private user;
    address private relayer;
    address private superAdmin = address(0x1);
    address private admin = address(0x2);
    address private sales = address(0x3);
    address private safeWallet = address(0x4);
    uint256 private userPrivateKey;
    uint256 private relayerPrivateKey;

    event Debug(string message);

    function setUp() public {
        // Deploy mock tokens and price feeds
        userPrivateKey = uint256(keccak256("user private key"));
        relayerPrivateKey = uint256(keccak256("relayer private key"));

        usdc = new MockERC20();
        usdc.initialize("USDC", "USDC", 6);

        // Set initial prices
        goldPriceFeed = new MockAggregator();
        goldPriceFeed.setPrice(2000 * 10 ** 8); // $2000/oz with 8 decimals
        usdcPriceFeed = new MockAggregator();
        usdcPriceFeed.setPrice(1 * 10 ** 8); // $1/USDC with 8 decimals

        // Derive the associated addresses
        user = vm.addr(userPrivateKey);
        relayer = vm.addr(relayerPrivateKey);

        // Deploy GoldPackToken and SalesContract
        vm.startPrank(superAdmin);

        // Deploy BurnVault
        //console.log("Deploying BurnVault");
        burnVault = new BurnVault();
        burnVault.initialize(superAdmin, admin);
        //console.log("BurnVault deployed");

        // Grant ADMIN_ROLE to superAdmin**
        //console.log("Granting DEFAULT_ADMIN_ROLE to superAdmin in BurnVault");
        burnVault.grantRole(burnVault.DEFAULT_ADMIN_ROLE(), superAdmin);
        //console.log("DEFAULT_ADMIN_ROLE granted to superAdmin");

        // Deploy GoldPackToken
        //console.log("Deploying GoldPackToken");
        gptToken = new GoldPackToken();
        gptToken.initialize(superAdmin, admin, sales, address(burnVault));
        //console.log("GoldPackToken deployed");

        // Deploy TradingVault
        //console.log("Deploying TradingVault");
        tradingVault = new TradingVault();
        tradingVault.initialize(safeWallet, admin, superAdmin);
        //console.log("TradingVault deployed");

        // Deploy SalesContract
        //console.log("Deploying SalesContract");
        salesContract = new SalesContract();
        salesContract.initialize(
            superAdmin, admin, sales, address(gptToken), address(goldPriceFeed), relayer, address(tradingVault)
        );
        salesContract.addAcceptedToken(address(usdc), address(usdcPriceFeed), 6);
        //console.log("SalesContract deployed");

        // Grant SALES_ROLE to SalesContract
        //console.log("Granting SALES_ROLE to SalesContract");
        gptToken.grantRole(gptToken.SALES_ROLE(), address(salesContract));
        //console.log("SALES_ROLE granted to SalesContract");

        // bool hasRole = gptToken.hasRole(gptToken.SALES_ROLE(), address(salesContract));
        //console.log("SalesContract has SALES_ROLE: %s", hasRole);

        // Set up token address in BurnVault
        //console.log("Setting token address in BurnVault");
        vm.startPrank(superAdmin);
        burnVault.setToken(ERC20Upgradeable(address(gptToken)));
        vm.stopPrank();
        //console.log("Token address set in BurnVault");

        // Set up token address in TradingVault
        //console.log("Setting token address in TradingVault");
        vm.startPrank(sales);
        salesContract.setSaleStage(ISalesContract.SaleStage.PublicSale);
        vm.stopPrank();
        //console.log("Token address set in TradingVault");
    }

    function testAuthorizePurchase() public {
        // Mint USDC to user
        usdc.mint(user, 2000 * 10 ** 6); // 2000 USDC with 6 decimals

        // Create and activate a sale round
        console.log("Creating and activating a sale round");
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the first round
        vm.stopPrank();
        console.log("Round activated");

        // Create order
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

        // Generate user signature
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        order.userSignature = abi.encodePacked(r, s, v);

        // Generate relayer signature
        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.prank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)

        // Execute purchase
        vm.prank(user);
        salesContract.authorizePurchase(order);

        // Verify results
        assertEq(gptToken.balanceOf(user), 10000_000000);
        assertEq(usdc.balanceOf(user), 0); // Should be 0 if exact
        assertEq(salesContract.nonces(user), 1);
    }

    function testAuthorizePurchaseInvalidNonce() public {
        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the first round
        vm.stopPrank();

        // Create order with invalid nonce
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 1, // Invalid nonce
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

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
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

        // Execute purchase and expect revert
        vm.expectRevert("Invalid nonce");
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testAuthorizePurchaseExpiredSignature() public {
        // Advance block timestamp to avoid underflow
        vm.warp(2 hours); // Sets block.timestamp to 2 hours

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the first round
        vm.stopPrank();

        // Create order with expired signature
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp - 1 hours, // Expired
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

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
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

        // Execute purchase and expect revert
        vm.expectRevert("Signature expired");
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testAuthorizePurchaseInvalidUserSignature() public {
        // Advance block timestamp to avoid underflow
        vm.warp(2 hours); // Sets block.timestamp to 2 hours

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the created round
        vm.stopPrank();

        // Create order with invalid user signature
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "", // Invalid signature
            relayerSignature: ""
        });

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
        vm.startPrank(user);
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

        // Execute purchase and expect revert
        vm.expectRevert("Invalid user signature");
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testAuthorizePurchaseInvalidRelayerSignature() public {
        // Advance block timestamp to avoid underflow
        vm.warp(2 hours); // Sets block.timestamp to 2 hours

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the created round
        vm.stopPrank();

        // Create order with invalid relayer signature
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: "" // Placeholder for invalid signature
        });

        // Generate user signature
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        order.userSignature = abi.encodePacked(r, s, v);

        order.relayerSignature = abi.encodePacked(r, s, v); // Invalid relayer signature

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

        // Execute purchase and expect revert
        vm.expectRevert("Invalid relayer signature");
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testAuthorizePurchaseInsufficientUSDCBalance() public {
        usdc.mint(user, 2000 * 10 ** 6); // Mint 1000 USDC

        // Advance block timestamp to avoid underflow
        vm.warp(2 hours); // Sets block.timestamp to 2 hours

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the created round
        vm.stopPrank();

        // Create order
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000, // 1 troy ounce worth of GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

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
        usdc.approve(address(tradingVault), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        usdc.burn(2000 * 10 ** 6); // Burn 2000 USDC
        vm.stopPrank();

        // Execute purchase and expect revert
        vm.expectRevert("Insufficient balance");
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testFailPurchaseWhenPaused() public {
        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days);
        salesContract.activateRound(salesContract.currentRoundId());
        vm.stopPrank();

        vm.prank(admin);
        // Pause the contract
        salesContract.pause();

        // Create order
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000,
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

        // Generate signatures
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        order.userSignature = abi.encodePacked(r, s, v);

        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(tradingVault), 1000 * 10 ** 6);
        vm.stopPrank();

        // Attempt purchase and expect revert due to paused contract
        vm.prank(user);
        salesContract.authorizePurchase(order);
    }

    function testPurchaseWhenUnpaused() public {
        usdc.mint(user, 2000 * 10 ** 6); // Mint 1000 USDC

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days);
        salesContract.activateRound(salesContract.currentRoundId());
        vm.stopPrank();

        vm.startPrank(superAdmin);
        // Pause the contract
        salesContract.pause();

        // Unpause the contract
        salesContract.unpause();
        vm.stopPrank();

        // Create order
        SalesContract.Order memory order = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 10_000_000000,
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

        // Generate signatures
        bytes32 userDigest = _getUserDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userDigest);
        order.userSignature = abi.encodePacked(r, s, v);

        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6);
        vm.stopPrank();

        // Execute purchase successfully
        vm.prank(user);
        salesContract.authorizePurchase(order);

        // Verify results
        assertEq(gptToken.balanceOf(user), 10_000_000000);
        assertEq(usdc.balanceOf(user), 0);
        assertEq(salesContract.nonces(user), 1);
    }

    function testMultiplePurchasesBySameUser() public {
        // Mint sufficient USDC to the user
        usdc.mint(user, 2_000 * 10 ** USDC_DECIMALS); // Mint 2,000 USDC

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(200_000_000000, block.timestamp, block.timestamp + 2 days); // 200,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId());
        vm.stopPrank();

        // First purchase: 50 GPT tokens
        SalesContract.Order memory order1 = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 5_000_000000, // 5000 GPT tokens
            nonce: 0,
            expiry: block.timestamp + 1 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

        // Generate user signature for order1
        bytes32 userDigest1 = _getUserDigest(order1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(userPrivateKey, userDigest1);
        order1.userSignature = abi.encodePacked(r1, s1, v1);

        // Generate relayer signature for order1
        bytes32 relayerDigest1 = _getRelayerDigest(order1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(relayerPrivateKey, relayerDigest1);
        order1.relayerSignature = abi.encodePacked(r2, s2, v2);

        // Approve USDC transfer for order1
        vm.startPrank(user);
        usdc.approve(address(salesContract), 1000 * 10 ** 6); // Approve 1000 USDC
        vm.stopPrank();

        // Execute first purchase
        vm.prank(user);
        salesContract.authorizePurchase(order1);

        // Second purchase: 30 GPT tokens
        SalesContract.Order memory order2 = ISalesContract.Order({
            roundId: salesContract.currentRoundId(),
            buyer: user,
            gptAmount: 3_000_000000, // 3000 GPT tokens
            nonce: 1,
            expiry: block.timestamp + 2 hours,
            paymentToken: address(usdc),
            userSignature: "",
            relayerSignature: ""
        });

        // Generate user signature for order2
        bytes32 userDigest2 = _getUserDigest(order2);
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(userPrivateKey, userDigest2);
        order2.userSignature = abi.encodePacked(r3, s3, v3);

        // Generate relayer signature for order2
        bytes32 relayerDigest2 = _getRelayerDigest(order2);
        (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(relayerPrivateKey, relayerDigest2);
        order2.relayerSignature = abi.encodePacked(r4, s4, v4);

        // Approve USDC transfer for order2
        vm.startPrank(user);
        usdc.approve(address(salesContract), 1000 * 10 ** 6); // Approve another 1000 USDC
        vm.stopPrank();

        // Execute second purchase
        vm.prank(user);
        salesContract.authorizePurchase(order2);

        // Verify results
        // We mint 2,000 USDC to the user, so the balance should be 400 USDC after two purchases
        // 10000 GPT tokens = 2000 USDC, so 1 GPT = 0.2 USDC
        // First purchase: 5000 GPT tokens = 1,000 USDC
        // Second purchase: 3000 GPT tokens = 600 USDC
        assertEq(usdc.balanceOf(user), 400 * 10 ** USDC_DECIMALS);
        assertEq(gptToken.balanceOf(user), 8_000 * 10 ** GPT_DECIMALS); // 5,000 + 3,000 GPT tokens
        assertEq(salesContract.nonces(user), 2); // Nonce incremented twice
    }

    function _getUserDigest(SalesContract.Order memory order) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                salesContract.USER_ORDER_TYPEHASH(),
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                block.chainid
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", salesContract.DOMAIN_SEPARATOR(), structHash));
    }

    function _getRelayerDigest(SalesContract.Order memory order) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                salesContract.RELAYER_ORDER_TYPEHASH(),
                order.roundId,
                order.buyer,
                order.gptAmount,
                order.nonce,
                order.expiry,
                order.paymentToken,
                order.userSignature,
                block.chainid
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", salesContract.DOMAIN_SEPARATOR(), structHash));
    }
}
