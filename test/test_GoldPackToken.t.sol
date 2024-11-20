// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/tokens/GoldPackToken.sol";
import "../src/vault/BurnVault.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract GoldPackTokenTest is Test {
    GoldPackToken public token;
    BurnVault public vault;

    // Roles
    address public superAdmin = address(5);
    address public admin = address(1);
    address public sales = address(2);
    address public user = address(3);
    address public burnVaultProxy;
    address public gptproxy;

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
        vm.startPrank(superAdmin);

        // Step 1: Deploy BurnVault first
        vault = new BurnVault();
        burnVaultProxy =
            Upgrades.deployUUPSProxy("BurnVault.sol", abi.encodeCall(BurnVault.initialize, (superAdmin, admin)));
        vault = BurnVault(burnVaultProxy);
        //console.log("Vault address:", address(vault));

        // Step 2: Deploy token with vault address
        /**
         * you need to specify the full contract identifier, which typically includes
         * both the file path and the contract name. This ensures that Upgrades.deployUUPSProxy can
         * uniquely locate the correct contract artifact.
         *      "src/tokens/GoldPackToken.sol:GoldPackToken",
         */
        token = new GoldPackToken();
        gptproxy = Upgrades.deployUUPSProxy(
            "GoldPackToken.sol:GoldPackToken", abi.encodeCall(GoldPackToken.initialize, (superAdmin, admin, sales))
        );
        token = GoldPackToken(gptproxy);
        //console.log("Token address:", address(token));

        // Step 3: Set token in vault
        BurnVault(burnVaultProxy).updateAcceptedTokens(ERC20BurnableUpgradeable(token));
        // Set burn vault address in token
        address burnvault = address(BurnVault(burnVaultProxy));
        GoldPackToken(gptproxy).setBurnVault(burnvault);

        // Step 4: Grant roles
        GoldPackToken(gptproxy).grantRole(token.SALES_ROLE(), sales);

        // Step 5: Grant Admin role to token contract in vault
        BurnVault(burnVaultProxy).grantRole(vault.ADMIN_ROLE(), address(token));

        vm.stopPrank();

        // Debug setup
        // console.log("Token's vault address:", address(token.burnVault()));

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
        assertTrue(BurnVault(burnVaultProxy).isAcceptedToken(address(token)));

        // Verify roles
        assertTrue(GoldPackToken(gptproxy).hasRole(GoldPackToken(gptproxy).DEFAULT_ADMIN_ROLE(), superAdmin));
        assertTrue(GoldPackToken(gptproxy).hasRole(GoldPackToken(gptproxy).ADMIN_ROLE(), admin));
        assertTrue(GoldPackToken(gptproxy).hasRole(GoldPackToken(gptproxy).SALES_ROLE(), sales));

        // Verify token properties
        assertEq(token.decimals(), 6);
        assertEq(GoldPackToken(gptproxy).getBurnVaultAddress(), address(vault));
    }

    function testPauseUnpause() public {
        vm.startPrank(superAdmin);

        // Test pause
        string memory reason = "Testing pause";
        vm.expectEmit(true, true, true, true);
        emit Paused(superAdmin, reason, block.timestamp);
        token.pause(reason);
        assertTrue(token.paused());

        // Test unpause
        reason = "Testing unpause";
        vm.expectEmit(true, true, true, true);
        emit Unpaused(superAdmin, reason, block.timestamp);
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
        address burnVaultAddress = token.getBurnVaultAddress();
        token.approve(burnVaultAddress, amount);
        // Approve vault to spend tokens
        token.depositToBurnVault(amount);
        assertEq(vault.getBalance(user), amount);

        vm.stopPrank();

        // Wait burn delay
        vm.warp(block.timestamp + vault.BURN_DELAY());

        // Burn tokens
        vm.prank(sales);
        token.burnFromVault(user);
        assertEq(vault.getBalance(user), 0);
    }

    // Failure cases
    // This test ensures that minting fails when the contract is paused
    function testFailMintingWhenPaused() public {
        vm.prank(admin);
        token.pause("Testing pause");

        vm.prank(sales);
        token.mint(user, token.TOKENS_PER_TROY_OUNCE());
    }

    function testFailUnauthorizedMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.SALES_ROLE())
        );
        vm.prank(user);
        token.mint(user, token.TOKENS_PER_TROY_OUNCE());
    }

    function testInvalidVaultDeposit() public {
        uint256 invalidAmount = token.TOKENS_PER_TROY_OUNCE() - 1;
        vm.expectRevert("GoldPackToken: amount must be a whole number of Troy ounces");
        vm.prank(user);
        token.depositToBurnVault(invalidAmount);
    }

    function testBurnBeforeDelay() public {
        uint256 amount = token.TOKENS_PER_TROY_OUNCE();

        // Setup: Mint tokens to the user
        vm.prank(sales);
        token.mint(user, amount);

        // Set the block timestamp to 1
        vm.warp(1);

        // Retrieve the BurnVault address
        address burnVaultAddress = token.getBurnVaultAddress();

        vm.startPrank(user);
        // Approve the BurnVault to spend tokens on behalf of the user
        token.approve(burnVaultAddress, amount);

        uint256 allowance = token.allowance(user, burnVaultAddress);
        assertEq(allowance, amount, "BurnVault does not have the correct allowance");

        // Deposit tokens to the BurnVault
        token.depositToBurnVault(amount);
        vm.stopPrank();

        // Attempt to burn tokens before the delay period has passed
        vm.expectRevert("BurnVault: burn delay not reached");
        vm.prank(sales);
        token.burnFromVault(user);
    }

    function testUnauthorizedBurn() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.SALES_ROLE())
        );
        vm.prank(user);
        token.burnFromVault(user);
    }
}
