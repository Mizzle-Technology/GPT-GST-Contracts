// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/Upgrades.sol";
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
    address private admin = address(1);
    address private nonAdmin = address(2);
    address private safeWallet = address(3);
    address private newSafeWallet = address(4); // For testing wallet updates

    // Events (Define only if you need to test event emissions)
    event WithdrawalWalletUpdated(address indexed newWallet);
    event WithdrawalThresholdUpdated(uint256 newThreshold);
    event Paused(address account);
    event Unpaused(address account);

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
        burnVault = new BurnVault();
        vm.startPrank(admin);
        burnVault.initialize();
        vm.stopPrank();

        // Deploy GoldPackToken
        gptToken = new GoldPackToken();
        vm.startPrank(admin);
        gptToken.initialize(address(burnVault));
        vm.stopPrank();

        // Deploy TradingVault
        tradingVault = new TradingVault();
        vm.startPrank(admin);
        tradingVault.initialize(safeWallet);
        vm.stopPrank();

        // Assign ADMIN_ROLE to admin
        vm.startPrank(admin);
        tradingVault.grantRole(ADMIN_ROLE, admin);
        vm.stopPrank();
    }

    // === Tests for setWithdrawalWallet ===

    function testSetWithdrawalWalletSuccess() public {
        // Emit event expectation
        vm.expectEmit(true, false, false, true);
        emit WithdrawalWalletUpdated(newSafeWallet);

        // Perform the action
        vm.prank(admin);
        bool success = tradingVault.setWithdrawalWallet(newSafeWallet);
        assertTrue(success);

        // Verify the state change
        assertEq(tradingVault.safeWallet(), newSafeWallet);
    }

    function testSetWithdrawalWalletUnauthorized() public {
        // Attempt to set withdrawal wallet by non-admin and expect revert
        vm.expectRevert(bytes("AccessControl: account is missing role ")); // Partial match
        vm.prank(nonAdmin);
        tradingVault.setWithdrawalWallet(newSafeWallet);
    }

    function testSetWithdrawalWalletToZeroAddress() public {
        // Attempt to set withdrawal wallet to zero address and expect revert
        vm.expectRevert(bytes("Invalid_Safe_wallet()")); // Ensure your contract reverts with this message
        vm.prank(admin);
        tradingVault.setWithdrawalWallet(address(0));
    }

    function testSetWithdrawalWalletSameAddress() public {
        // Attempt to set withdrawal wallet to the current address and expect revert
        vm.expectRevert(bytes("Same threshold")); // Ensure your contract reverts with this message
        vm.prank(admin);
        tradingVault.setWithdrawalWallet(safeWallet);
    }

    // === Tests for setWithdrawalThreshold ===

    function testSetWithdrawalThresholdSuccess() public {
        uint256 newThreshold = 500000 * 10 ** 6; // Example: 500,000 USDC

        // Emit event expectation
        vm.expectEmit(true, false, false, true);
        emit WithdrawalThresholdUpdated(newThreshold);

        // Perform the action
        vm.prank(admin);
        bool success = tradingVault.setWithdrawalThreshold(newThreshold);
        assertTrue(success);

        // Verify the state change
        assertEq(tradingVault.WITHDRAWAL_THRESHOLD(), newThreshold);
    }

    function testSetWithdrawalThresholdUnauthorized() public {
        uint256 newThreshold = 500000 * 10 ** 6; // Example: 500,000 USDC

        // Attempt to set withdrawal threshold by non-default admin and expect revert
        vm.expectRevert(bytes("AccessControl: account is missing role "));
        vm.prank(nonAdmin);
        tradingVault.setWithdrawalThreshold(newThreshold);
    }

    function testSetWithdrawalThresholdToZero() public {
        // Attempt to set withdrawal threshold to zero and expect revert
        vm.expectRevert(bytes("Threshold must be greater than 0"));
        vm.prank(admin);
        tradingVault.setWithdrawalThreshold(0);
    }

    function testSetWithdrawalThresholdSameValue() public {
        uint256 currentThreshold = tradingVault.WITHDRAWAL_THRESHOLD();

        // Attempt to set the same threshold and expect revert
        vm.expectRevert(bytes("Same threshold"));
        vm.prank(admin);
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
        vm.expectRevert(bytes("AccessControl: account is missing role "));
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
        vm.expectRevert(bytes("AccessControl: account is missing role "));
        vm.prank(nonAdmin);
        tradingVault.unpause();
    }

    // === Tests for _authorizeUpgrade ===

    function testAuthorizeUpgradeAuthorized() public {
        address newImplementation = address(4);

        // Perform the action
        vm.prank(admin);
        tradingVault.upgradeToAndCall(newImplementation);

        // Since TradingVault is likely a proxy, further checks would require interacting with the proxy.
        // For simplicity, we assume the upgrade authorization passed if no revert occurred.
    }

    function testAuthorizeUpgradeUnauthorized() public {
        address newImplementation = address(4);

        // Attempt to authorize upgrade by non-default admin and expect revert
        vm.expectRevert(bytes("AccessControl: account is missing role "));
        vm.prank(nonAdmin);
        tradingVault.upgradeToAndCall(newImplementation);
    }

    // === Additional Helper Functions and Events ===

    // Note: Removed duplicated event declarations and custom error definitions.
}
