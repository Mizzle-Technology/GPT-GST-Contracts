// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/vault/BurnVault.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// Interface for the callback
interface IReentrancyAttack {
    function reenter() external;
}

// Reentrant ERC20 Token for testing
contract ReentrantERC20 is ERC20Upgradeable, ERC20BurnableUpgradeable {
    uint8 private _customDecimals;

    function initialize(string memory name, string memory symbol, uint8 decimals_) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        _customDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
        // If the caller is a contract, invoke reenter
        if (isContract(msg.sender)) {
            IReentrancyAttack(msg.sender).reenter();
        }
    }

    // Override transferFrom to include a callback for reentrancy
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Normal transferFrom logic
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);

        // If the sender is a contract, invoke the reenter function
        if (isContract(from)) {
            IReentrancyAttack(from).reenter();
        }

        return true;
    }

    // Helper function to check if an address is a contract
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}

// Mock ERC20 Token for testing
contract MockERC20 is ERC20Upgradeable, ERC20BurnableUpgradeable {
    uint8 private _customDecimals;

    function initialize(string memory name, string memory symbol, uint8 decimals_) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();

        _customDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}

// Malicious contract for reentrancy tests
contract MaliciousContract is IReentrancyAttack {
    BurnVault public vault;
    ReentrantERC20 public token;
    bool public reentered;
    address public targetAccount;

    constructor(BurnVault _vault, ReentrantERC20 _token) {
        vault = _vault;
        token = _token;
        reentered = false;
    }

    function attackDeposit(uint256 amount) public {
        token.approve(address(vault), amount);
        vault.depositTokens(address(this), amount);
    }

    // This function will be called during transferFrom in ReentrantERC20
    function reenter() external override {
        if (!reentered) {
            reentered = true;
            // Attempt to reenter depositTokens
            vault.depositTokens(address(this), 1);

            // Attempt to reenter burnTokens
            vault.burnTokens(targetAccount);
        }
    }

    function attackBurn(address account) public {
        targetAccount = account;
        vault.burnTokens(account);
    }
}

contract TestBurnVault is Test {
    event TokensDeposited(address indexed from, uint256 amount, uint256 timestamp);
    event TokensBurned(address indexed admin, address indexed account, uint256 amount);

    BurnVault vault;
    MockERC20 token;
    address superAdmin = address(0x1);
    address admin = address(0x2);
    address user = address(0x3);
    address newAdmin = address(0x4);
    address nonAdmin = address(0x5);

    function setUp() public {
        // Deploy MockERC20
        token = new MockERC20();
        token.initialize("MockToken", "MTK", 18);

        // Deploy BurnVault
        vm.startPrank(superAdmin);
        vault = new BurnVault();
        vm.stopPrank();
    }

    // 1. Initialization Tests

    function test_initialize_success() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Verify roles
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), superAdmin));
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));

        // Verify _initialized is false
        // Note: _initialized is private, so we rely on behavior or events
        // Alternatively, expose a getter in BurnVault for testing purposes
    }

    function test_initialize_zero_super_revert() public {
        vm.startPrank(superAdmin);
        vm.expectRevert(bytes("BurnVault: the default admin cannot be the zero address"));
        vault.initialize(address(0), admin);
        vm.stopPrank();
    }

    function test_initialize_zero_admin_revert() public {
        vm.startPrank(superAdmin);
        vm.expectRevert(bytes("BurnVault: the admin cannot be the zero address"));
        vault.initialize(superAdmin, address(0));
        vm.stopPrank();
    }

    function test_initialize_reinitialization_revert() public {
        // First initialization
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Attempt re-initialization
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(superAdmin, admin);
    }

    // 2. setToken Function Tests

    function test_setToken_success() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Verify token is set
        assertEq(address(vault.token()), address(token));

        // Verify _initialized is true by attempting to setToken again
        vm.startPrank(superAdmin);
        vm.expectRevert(bytes("BurnVault: already initialized"));
        vault.setToken(token);
        vm.stopPrank();
    }

    function test_setToken_nonAdmin_revert() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", nonAdmin, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.setToken(token);
        vm.stopPrank();
    }

    function test_setToken_zero_address_revert() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vm.expectRevert(bytes("BurnVault: token cannot be the zero address"));
        vault.setToken(ERC20Upgradeable(address(0)));
        vm.stopPrank();
    }

    function test_setToken_resetting_revert() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);

        MockERC20 newToken = new MockERC20();
        newToken.initialize("NewToken", "NTK", 18);
        vm.expectRevert(bytes("BurnVault: already initialized"));
        vault.setToken(newToken);
        vm.stopPrank();
    }

    // 3. Access Control Tests

    function test_verify_default_admin_role() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), superAdmin));
    }

    function test_verify_admin_role() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));
    }

    function test_grant_revoke_admin_role() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        vm.startPrank(superAdmin);
        vault.grantRole(vault.ADMIN_ROLE(), newAdmin);
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), newAdmin));

        vault.revokeRole(vault.ADMIN_ROLE(), newAdmin);
        assertFalse(vault.hasRole(vault.ADMIN_ROLE(), newAdmin));
        vm.stopPrank();
    }

    // 4. Pausable Functionality Tests

    function test_pause_unpause_by_admin() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);

        vault.pause();
        // Assuming BurnVault has a paused() function
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }

    function test_pause_by_non_admin_revert() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", nonAdmin, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.pause();
        vm.stopPrank();
    }

    // 5. Deposit Functionality Tests

    function test_deposit_success() public {
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Mint tokens to user
        token.mint(user, 1000);

        // Approve vault
        vm.startPrank(user);
        token.approve(address(vault), 1000);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit TokensDeposited(user, 500, block.timestamp);

        // Deposit tokens
        vault.depositTokens(user, 500);
        vm.stopPrank();

        // Verify deposit
        (uint256 amount,) = vault.deposits(user);
        assertEq(amount, 500);
    }

    function test_deposit_without_approval_revert() public {
        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Mint tokens to user
        token.mint(user, 1000);

        // Do not approve
        vm.startPrank(user);

        vm.expectRevert();
        vault.depositTokens(user, 500);
        vm.stopPrank();
    }

    function test_deposit_zero_revert() public {
        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Approve vault
        vm.startPrank(user);
        token.approve(address(vault), 1000);

        // Attempt to deposit zero
        vm.expectRevert(bytes("BurnVault: amount must be greater than zero"));
        vault.depositTokens(user, 0);
        vm.stopPrank();
    }

    // 6. Burn Functionality Tests

    function test_burn_success_after_delay() public {
        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Mint and deposit tokens
        token.mint(user, 1000);
        vm.startPrank(user);
        token.approve(address(vault), 1000);
        vault.depositTokens(user, 500);
        vm.stopPrank();

        // Verify vault's balance after deposit
        uint256 vaultBalance = token.balanceOf(address(vault));
        assertEq(vaultBalance, 500, "Vault balance should be 500 after deposit");

        // Advance time
        vm.warp(block.timestamp + vault.BURN_DELAY() + 1);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit TokensBurned(admin, user, 500);

        // Burn tokens
        vm.startPrank(admin);
        vault.burnTokens(user);
        vm.stopPrank();

        // Verify deposit is deleted
        (uint256 amount,) = vault.deposits(user);
        assertEq(amount, 0, "Deposit amount should be zero after burn");

        // Verify vault's balance after burn
        vaultBalance = token.balanceOf(address(vault));
        assertEq(vaultBalance, 0, "Vault balance should be zero after burn");
    }

    function test_burn_before_delay_revert() public {
        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Mint and deposit tokens
        token.mint(user, 1000);
        vm.startPrank(user);
        token.approve(address(vault), 1000);
        vault.depositTokens(user, 500);
        vm.stopPrank();

        // Attempt to burn before delay
        vm.startPrank(admin);
        vm.expectRevert(bytes("BurnVault: burn delay not reached"));
        vault.burnTokens(user);
        vm.stopPrank();
    }

    function test_burn_by_non_admin_revert() public {
        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(token);
        vm.stopPrank();

        // Mint and deposit tokens
        token.mint(user, 1000);
        vm.startPrank(user);
        token.approve(address(vault), 1000);
        vault.depositTokens(user, 500);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + vault.BURN_DELAY() + 1);

        // Attempt to burn by non-admin
        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", nonAdmin, vault.ADMIN_ROLE())
        );
        vault.burnTokens(user);
        vm.stopPrank();
    }

    // 7. Reentrancy Tests

    function test_reentrancy_deposit_revert() public {
        // Deploy ReentrantERC20
        ReentrantERC20 reentrantToken = new ReentrantERC20();
        reentrantToken.initialize("ReentrantToken", "RTK", 18);

        // Deploy malicious contract
        MaliciousContract mal = new MaliciousContract(vault, reentrantToken);

        // Set token
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(reentrantToken);
        vm.stopPrank();

        // Mint tokens to malicious contract
        reentrantToken.mint(address(mal), 1000);

        // Attempt reentrancy
        vm.startPrank(address(mal));
        reentrantToken.approve(address(vault), 1000);

        // Expect revert due to reentrancy guard
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        mal.attackDeposit(500);
        vm.stopPrank();
    }

    function test_reentrancy_burn_revert() public {
        // Deploy ReentrantERC20
        ReentrantERC20 reentrantToken = new ReentrantERC20();
        reentrantToken.initialize("ReentrantToken", "RTK", 18);

        // Deploy malicious contract
        MaliciousContract mal = new MaliciousContract(vault, reentrantToken);

        // Set token and grant ADMIN_ROLE to MaliciousContract
        vm.startPrank(superAdmin);
        vault.initialize(superAdmin, admin);
        vault.setToken(reentrantToken);
        vault.grantRole(vault.ADMIN_ROLE(), address(mal));
        vm.stopPrank();

        // Mint and deposit tokens
        reentrantToken.mint(user, 1000);
        vm.startPrank(user);
        reentrantToken.approve(address(vault), 1000);
        vault.depositTokens(user, 500);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + vault.BURN_DELAY() + 1);

        // Attempt reentrancy
        vm.startPrank(admin);
        vm.expectRevert();
        mal.attackBurn(user);
        vm.stopPrank();
    }
}
