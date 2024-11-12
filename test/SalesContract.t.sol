// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/sales/SalesContract.sol";
import "../src/vault/BurnVault.sol";

contract SalesContractTest is Test {
    // Define constants at the contract level
    uint256 public constant USDC_DECIMALS = 6;
    uint256 public constant GPT_DECIMALS = 6;

    GoldPackToken private gptToken;
    SalesContract private salesContract;
    MockERC20 private usdc;
    MockAggregator private goldPriceFeed;
    MockAggregator private usdcPriceFeed;

    address private user;
    address private relayer;
    address private admin = address(1);
    address private sales = address(2);
    uint256 private userPrivateKey;
    uint256 private relayerPrivateKey;

    function setUp() public {
        // Deploy mock tokens and price feeds
        usdc = new MockERC20("USDC", "USDC", 6);
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
        vm.prank(admin);
        gptToken = new GoldPackToken(address(burnVault));

        // Note: SalesContract constructor grants DEFAULT_ADMIN_ROLE to msg.sender
        vm.prank(admin); // Set admin as deployer
        salesContract = new SalesContract(address(gptToken), address(goldPriceFeed), relayer);

        // Grant SALES_ROLE to SalesContract
        vm.startPrank(admin);
        gptToken.grantRole(gptToken.SALES_ROLE(), address(salesContract));
        vm.stopPrank();

        // Set up token address in BurnVault
        burnVault.setToken(ERC20(address(gptToken)));

        // Setup roles and configuration
        vm.startPrank(admin);
        salesContract.grantRole(salesContract.SALES_MANAGER_ROLE(), sales);
        salesContract.addAcceptedToken(address(usdc), address(usdcPriceFeed), 6);
        salesContract.setSaleStage(SalesContract.SaleStage.PublicSale);
        vm.stopPrank();
    }

    function testAuthorizePurchase() public {
        // Mint USDC to user
        usdc.mint(user, 2000 * 10 ** 6); // 2000 USDC with 6 decimals

        // Create and activate a sale round
        vm.startPrank(sales);
        salesContract.createRound(100_000_000000, block.timestamp, block.timestamp + 1 days); // Create a round with 100,000 GPT tokens
        salesContract.activateRound(salesContract.currentRoundId()); // Activate the first round
        vm.stopPrank();

        // Create order
        SalesContract.Order memory order = SalesContract.Order({
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
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
        vm.stopPrank();

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
        SalesContract.Order memory order = SalesContract.Order({
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
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
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
        SalesContract.Order memory order = SalesContract.Order({
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
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
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
        SalesContract.Order memory order = SalesContract.Order({
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
        order.relayerSignature = abi.encodePacked(r, s, v);

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
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
        SalesContract.Order memory order = SalesContract.Order({
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

        // Generate a valid relayer signature and then modify it to be invalid
        bytes32 relayerDigest = _getRelayerDigest(order);
        (v, r, s) = vm.sign(relayerPrivateKey, relayerDigest);
        bytes memory validRelayerSignature = abi.encodePacked(r, s, v);
        bytes memory invalidRelayerSignature = validRelayerSignature;
        invalidRelayerSignature[0] = 0x00; // Modify the signature to make it invalid
        order.relayerSignature = invalidRelayerSignature;

        // Approve USDC transfer
        vm.startPrank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
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
        SalesContract.Order memory order = SalesContract.Order({
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
        usdc.approve(address(salesContract), 2000 * 10 ** 6); // Approve 2000 USDC (with 6 decimals)
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
        SalesContract.Order memory order = SalesContract.Order({
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
        usdc.approve(address(salesContract), 1000 * 10 ** 6);
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

        vm.startPrank(admin);
        // Pause the contract
        salesContract.pause();

        // Unpause the contract
        salesContract.unpause();
        vm.stopPrank();

        // Create order
        SalesContract.Order memory order = SalesContract.Order({
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
        SalesContract.Order memory order1 = SalesContract.Order({
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
        SalesContract.Order memory order2 = SalesContract.Order({
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

// Mock contracts
contract MockERC20 is ERC20, ERC20Burnable {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Add proper MockAggregator implementation
contract MockAggregator {
    int256 private _price;
    uint8 private constant _decimals = 8;

    constructor() {
        _price = 0;
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    // Function to get the latest answer
    function latestAnswer() external view returns (int256) {
        return _price;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            1, // roundId
            _price, // price with 8 decimals
            block.timestamp,
            block.timestamp,
            1
        );
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }
}
