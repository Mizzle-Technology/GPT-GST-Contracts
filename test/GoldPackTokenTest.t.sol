// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/vault/BurnVault.sol";

contract GoldPackTokenTest is Test {
    GoldPackToken public token;
    BurnVault public vault;

    address public admin = address(1);
    address public sales = address(2);
    address public user = address(3);

    // Events
    event Mint(address indexed to, uint256 amount);
    event VaultDeposit(address indexed from, uint256 amount);
    event VaultBurn(address indexed account, uint256 amount);
    event AdminRoleGranted(address indexed account);
    event AdminRoleRevoked(address indexed account);
    event SalesRoleGranted(address indexed account);
    event SalesRoleRevoked(address indexed account);
    event Paused(address account, string reason, uint256 timestamp);
    event Unpaused(address account, string reason, uint256 timestamp);

    function setUp() public {
        vm.startPrank(admin);

        // Step 1: Deploy BurnVault first
        vault = new BurnVault();
        vault.initialize();

        console.log("Vault address:", address(vault));

        // Step 2: Deploy token with vault address
        token = new GoldPackToken(address(vault));
        console.log("Token address:", address(token));

        // Step 3: Set token in vault
        vault.setToken(ERC20(address(token)));

        // Step 4: Grant roles
        token.grantRole(token.SALES_ROLE(), sales);

        // Step 5: Grant Admin role to token contract in vault
        vault.grantRole(vault.ADMIN_ROLE(), address(token));

        vm.stopPrank();

        // Debug setup
        console.log("Token's vault address:", address(token.burnVault()));

        // Verify setup with better error message
        if (address(token.burnVault()) != address(vault)) {
            revert(
                string(
                    abi.encodePacked(
                        "Vault address mismatch: expected ",
                        addressToString(address(vault)),
                        " but got ",
                        addressToString(address(token.burnVault()))
                    )
                )
            );
        }
    }

    // Helper function
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function testSetup() public view {
        // Verify that the BurnVault has the correct token address
        assertEq(address(vault.token()), address(token));

        // Verify roles
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.SALES_ROLE(), sales));

        // Verify token properties
        assertEq(token.decimals(), 6);
        assertEq(address(token.burnVault()), address(vault));
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);

        // Test pause
        string memory reason = "Testing pause";
        vm.expectEmit(true, true, true, true);
        emit Paused(admin, reason, block.timestamp);
        token.pause(reason);
        assertTrue(token.paused());

        // Test unpause
        reason = "Testing unpause";
        vm.expectEmit(true, true, true, true);
        emit Unpaused(admin, reason, block.timestamp);
        token.unpause(reason);
        assertFalse(token.paused());

        vm.stopPrank();
    }

    function testMinting() public {
        uint256 amount = token.TOKENS_PER_TROY_OUNCE();

        vm.startPrank(sales);
        token.mint(user, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user), amount);
    }

    function testVaultOperations() public {
        uint256 amount = token.TOKENS_PER_TROY_OUNCE();

        // Mint tokens to user
        vm.prank(sales);
        token.mint(user, amount);

        // Deposit to vault
        vm.startPrank(user);

        // Approve vault to spend tokens
        token.depositToBurnVault(amount);
        assertEq(vault.getBalance(user), amount);

        vm.stopPrank();

        // Wait burn delay
        vm.warp(block.timestamp + vault.BURN_DELAY());

        // Burn tokens
        vm.prank(admin);
        token.burnFromVault(user);
        assertEq(vault.getBalance(user), 0);
    }

    function testRoleManagement() public {
        address newAdmin = address(4);

        vm.startPrank(admin);

        // Grant new admin role
        vm.expectEmit(true, false, false, false);
        emit AdminRoleGranted(newAdmin);
        token.grantAdminRole(newAdmin);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), newAdmin));

        // Revoke admin role
        vm.expectEmit(true, false, false, false);
        emit AdminRoleRevoked(newAdmin);
        token.revokeAdminRole(newAdmin);
        assertFalse(token.hasRole(token.ADMIN_ROLE(), newAdmin));

        vm.stopPrank();
    }

    // Failure cases
    function testFailMintingWhenPaused() public {
        vm.prank(admin);
        token.pause("Testing pause");

        vm.prank(sales);
        token.mint(user, token.TOKENS_PER_TROY_OUNCE());
    }

    function testFailUnauthorizedMint() public {
        vm.prank(user);
        token.mint(user, token.TOKENS_PER_TROY_OUNCE());
    }

    function testFailInvalidVaultDeposit() public {
        uint256 invalidAmount = token.TOKENS_PER_TROY_OUNCE() - 1;
        vm.prank(user);
        token.depositToBurnVault(invalidAmount);
    }

    function testFailBurnBeforeDelay() public {
        uint256 amount = token.TOKENS_PER_TROY_OUNCE();

        // Setup
        vm.prank(sales);
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(token), amount);
        token.depositToBurnVault(amount);
        vm.stopPrank();

        // Try burn immediately
        vm.prank(sales);
        token.burnFromVault(user);
    }

    function testFailUnauthorizedBurn() public {
        vm.prank(user);
        token.burnFromVault(user);
    }
}
