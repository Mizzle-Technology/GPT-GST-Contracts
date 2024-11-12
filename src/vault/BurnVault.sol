// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/proxy/utils/Initializable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";

contract BurnVault is Initializable, AccessControl, ReentrancyGuard {
    using SafeERC20 for ERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Set burn delay to 7 days
    uint256 public constant BURN_DELAY = 7 days;

    ERC20 public token;

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => Deposit) public deposits;

    event TokensDeposited(address indexed from, uint256 amount, uint256 timestamp);
    event TokensBurned(address indexed admin, address indexed account, uint256 amount);

    bool private _initialized;

    /**
     * @dev First initialization step - sets up roles
     */
    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _initialized = false;
    }

    /**
     * @dev Second initialization step - sets token address
     * @param _token The ERC20 token to be burned
     */
    function setToken(ERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!_initialized, "BurnVault: already initialized");
        require(address(_token) != address(0), "BurnVault: zero address");
        token = _token;
        _initialized = true;
    }

    /**
     * @dev Deposits `amount` tokens to the vault.
     * @param amount The amount of tokens to deposit.
     * @param user_account The account to deposit tokens to.
     * Requirements:
     * - `amount` must be greater than zero.
     * - Caller must have approved the vault to spend `amount` tokens.
     * Emits a {TokensDeposited} event.
     */
    function depositTokens(address user_account, uint256 amount) public nonReentrant {
        require(amount > 0, "BurnVault: amount must be greater than zero");

        // Update the deposit record
        deposits[user_account] = Deposit({
            amount: deposits[user_account].amount + amount, // Accumulate deposits
            timestamp: block.timestamp
        });

        emit TokensDeposited(user_account, amount, block.timestamp);
    }

    /**
     * @dev Burns tokens from the specified account after the burn delay.
     * @param account The account whose tokens to burn.
     * Requirements:
     * - Caller must have `ADMIN_ROLE`.
     * - `BURN_DELAY` must have passed since the last deposit.
     * Emits a {TokensBurned} event.
     */
    function burnTokens(address account) public nonReentrant onlyRole(ADMIN_ROLE) {
        Deposit storage deposit = deposits[account];
        require(deposit.amount > 0, "BurnVault: no tokens to burn");
        require(block.timestamp >= deposit.timestamp + BURN_DELAY, "BurnVault: burn delay not reached");

        uint256 amountToBurn = deposit.amount;

        // Verify vault has enough tokens
        require(ERC20(token).balanceOf(address(this)) >= amountToBurn, "BurnVault: insufficient vault balance");

        // Burn tokens held by vault
        ERC20Burnable(address(token)).burn(amountToBurn);

        delete deposits[account];
        emit TokensBurned(msg.sender, account, amountToBurn);
    }

    /**
     * @dev Returns the balance of the specified account.
     * @param account The account whose balance to return.
     * @return The balance of the account.
     */
    function getBalance(address account) public view returns (uint256) {
        return deposits[account].amount;
    }
}
