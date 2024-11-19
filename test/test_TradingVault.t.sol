// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/vault/TradingVault.sol"; // Adjust the import path as necessary
import "../src/vault/BurnVault.sol"; // Ensure correct path
import "../src/tokens/GoldPackToken.sol"; // Ensure correct path
import "./Mocks.sol"; // Mock contracts

contract TradingVaultTest is Test {
    // Mocked Contracts
    MockERC20 private usdc;
    MockAggregator private goldPriceFeed;
    MockAggregator private usdcPriceFeed;
    BurnVault private burnVault;
    GoldPackToken private gptToken;
    TradingVault private tradingVault;

    // Roles
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00; // OpenZeppelin default
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Addresses
    address private superAdmin = address(5);
    address private admin = address(1);
    address private nonAdmin = address(6);
    address private sales = address(2);
    address private safeWallet = address(3);
    address private newSafeWallet = address(4); // For testing wallet updates

    // Events (Define only if you need to test event emissions)
    event WithdrawalWalletUpdated(address indexed newWallet);
    event WithdrawalThresholdUpdated(uint256 newThreshold);
    event Paused(address account);
    event Unpaused(address account);

    // Custom Errors
    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public {
        // Deploy Mock Contracts
        usdc = new MockERC20();
        usdc.initialize("USDC", "USD Coin", 6);

        goldPriceFeed = new MockAggregator();
        usdcPriceFeed = new MockAggregator();

        // Set initial prices
        goldPriceFeed.setPrice(2000 * 10 ** 8); // $2000/oz with 8 decimals
        usdcPriceFeed.setPrice(1 * 10 ** 8); // $1/USDC with 8 decimals

        // Deploy BurnVault
        vm.startPrank(superAdmin);
        burnVault = new BurnVault();
        burnVault.initialize(superAdmin, admin);

        // Deploy GoldPackToken
        gptToken = new GoldPackToken();
        gptToken.initialize(superAdmin, admin, sales, address(burnVault));

        // Initialize TradingVault with supported tokens
        tradingVault = new TradingVault();
        tradingVault.initialize(safeWallet, admin, superAdmin);

        vm.stopPrank();
    }

    // === Tests for setWithdrawalWallet ===

    function testSetWithdrawalWalletSuccess() public {
        // Emit event expectation
        vm.expectEmit(true, false, false, true);
        emit WithdrawalWalletUpdated(newSafeWallet);

        // Perform the action
        vm.prank(superAdmin);
        bool success = tradingVault.setWithdrawalWallet(newSafeWallet);
        assertTrue(success);

        // Verify the state change
        assertEq(tradingVault.safeWallet(), newSafeWallet);
    }

    function testFailSetWithdrawalWalletUnauthorized() public {
        // Attempt to set withdrawal wallet by non-admin and expect revert
        vm.prank(nonAdmin);
        tradingVault.setWithdrawalWallet(newSafeWallet);

        // Verify the state change
        assertEq(tradingVault.safeWallet(), safeWallet);
    }

    function testSetWithdrawalWalletToZeroAddress() public {
        // Attempt to set withdrawal wallet to zero address and expect revert
        vm.expectRevert(bytes("Invalid wallet address"));
        vm.prank(superAdmin);
        tradingVault.setWithdrawalWallet(address(0));
    }

    function testSetWithdrawalWalletSameAddress() public {
        // Attempt to set withdrawal wallet to the current address and expect revert
        vm.expectRevert(bytes("Same wallet address"));
        vm.prank(superAdmin);
        tradingVault.setWithdrawalWallet(safeWallet);
    }

    // === Tests for setWithdrawalThreshold ===

    function testSetWithdrawalThresholdSuccess() public {
        uint256 newThreshold = 500000 * 10 ** 6; // Example: 500,000 USDC

        // Perform the action
        vm.prank(superAdmin);
        bool success = tradingVault.setWithdrawalThreshold(newThreshold);
        assertTrue(success);

        // Verify the state change
        assertEq(tradingVault.WITHDRAWAL_THRESHOLD(), newThreshold);
    }

    function testSetWithdrawalThresholdUnauthorized() public {
        uint256 newThreshold = 500000 * 10 ** 6; // Example: 500,000 USDC

        // Attempt to set withdrawal threshold by non-default admin and expect revert
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE));
        vm.prank(nonAdmin);
        tradingVault.setWithdrawalThreshold(newThreshold);
    }

    function testSetWithdrawalThresholdToZero() public {
        // Attempt to set withdrawal threshold to zero and expect revert
        vm.expectRevert(bytes("Threshold must be greater than 0"));
        vm.prank(superAdmin);
        tradingVault.setWithdrawalThreshold(0);
    }

    function testSetWithdrawalThresholdSameValue() public {
        uint256 currentThreshold = tradingVault.WITHDRAWAL_THRESHOLD();

        // Attempt to set the same threshold and expect revert
        vm.expectRevert(bytes("Same threshold"));
        vm.prank(superAdmin);
        tradingVault.setWithdrawalThreshold(currentThreshold);
    }

    // === Tests for Pausable Functions ===

    function testPauseSuccess() public {
        // Emit event expectation
        vm.expectEmit(true, false, false, true);
        emit Paused(admin);

        // Perform the action
        vm.prank(admin);
        tradingVault.pause();

        // Verify the state change
        assertTrue(tradingVault.paused());
    }

    function testPauseUnauthorized() public {
        // Attempt to pause by non-admin and expect revert
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE));
        vm.prank(nonAdmin);
        tradingVault.pause();
    }

    function testUnpauseSuccess() public {
        // First, pause the contract
        vm.prank(admin);
        tradingVault.pause();
        assertTrue(tradingVault.paused());

        // Emit event expectation
        vm.expectEmit(true, false, false, true);
        emit Unpaused(admin);

        // Perform the action
        vm.prank(admin);
        tradingVault.unpause();

        // Verify the state change
        assertFalse(tradingVault.paused());
    }

    function testUnpauseUnauthorized() public {
        // First, pause the contract
        vm.prank(admin);
        tradingVault.pause();
        assertTrue(tradingVault.paused());

        // Attempt to unpause by non-admin and expect revert
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, nonAdmin, ADMIN_ROLE));
        vm.prank(nonAdmin);
        tradingVault.unpause();
    }

    function testUpgradeToV2() public {
        // Start pranking as admin before deploying the proxy
        vm.startPrank(superAdmin);

        // Deploy Proxy with initialize called by admin
        address proxy = Upgrades.deployUUPSProxy(
            "TradingVault.sol", abi.encodeCall(TradingVault.initialize, (safeWallet, admin, superAdmin))
        );

        TradingVault proxyContract = TradingVault(proxy);

        // No need to grant DEFAULT_ADMIN_ROLE since admin is the initializer
        vm.stopPrank();

        // Deploy V2 Implementation
        TradingVaultV2 v2_impl = new TradingVaultV2();

        // Prepare initialization data with newSafeWallet
        bytes memory emptyData = "";

        // Start pranking as admin to perform the upgrade
        vm.startPrank(superAdmin);

        // Perform upgrade with initialization
        proxyContract.upgradeToAndCall(address(v2_impl), emptyData);

        TradingVaultV2(proxy).setWithdrawalWallet(newSafeWallet);

        vm.stopPrank();

        // Verify upgrade was successful by calling V2 function
        TradingVaultV2 upgradedProxy = TradingVaultV2(proxy);
        assertEq(upgradedProxy.version(), "V2", "Upgrade to V2 failed");

        // Verify state preservation
        assertEq(upgradedProxy.safeWallet(), newSafeWallet, "Safe wallet not updated correctly");
    }
}
