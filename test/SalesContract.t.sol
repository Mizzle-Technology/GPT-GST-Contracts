// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/sales/SalesContract.sol";
import "../src/vault/BurnVault.sol";
import "@openzeppelin/utils/cryptography/ECDSA.sol";

contract SalesContractTest is Test {
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
        // Mock USDC token
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mock Chainlink Aggregator
        goldPriceFeed = new MockAggregator();
        goldPriceFeed.setPrice(2000 * 10 ** 8); // $2000/oz

        usdcPriceFeed = new MockAggregator();
        usdcPriceFeed.setPrice(1 * 10 ** 8); // $1/USDC

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
        gptToken = new GoldPackToken(address(burnVault));
        salesContract = new SalesContract(address(gptToken), address(goldPriceFeed), relayer);

        // Set up token address in BurnVault
        burnVault.setToken(ERC20(address(gptToken)));

        // Setup roles and configuration
        vm.startPrank(admin);
        salesContract.grantRole(salesContract.ADMIN_ROLE(), admin);
        salesContract.grantRole(salesContract.SALES_MANAGER_ROLE(), sales);
        salesContract.addAcceptedToken(address(usdc), address(usdcPriceFeed), 6);
        salesContract.setSaleStage(SalesContract.SaleStage.PublicSale);
        vm.stopPrank();

        // Mint USDC to user
        usdc.mint(user, 2000 * 10 ** 6); // 2000 USDC
    }

    function testAuthorizePurchase() public {
        // Create order
        SalesContract.Order memory order = SalesContract.Order({
            buyer: user,
            gptAmount: 10000, // 1 troy ounce
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

        // Execute purchase
        vm.startPrank(user);
        usdc.approve(address(salesContract), 2000 * 10 ** 6);
        salesContract.authorizePurchase(order);
        vm.stopPrank();

        // Verify results
        assertEq(gptToken.balanceOf(user), 10000);
        assertEq(usdc.balanceOf(user), 0);
        assertEq(salesContract.nonces(user), 1);
    }

    function _getUserDigest(SalesContract.Order memory order) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                salesContract.USER_ORDER_TYPEHASH(),
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
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockAggregator {
    int256 private _price;

    constructor() {
        _price = 2000 * 10 ** 8; // Current gold price ~$2000/oz
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            92233720368547778907, // Example roundId from real feed
            _price,
            block.timestamp - 3600, // 1 hour ago
            block.timestamp,
            92233720368547778907
        );
    }

    function decimals() external pure returns (uint8) {
        return 8; // XAU/USD uses 8 decimals
    }

    // Test helper
    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
}
