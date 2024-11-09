// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";

contract BurnVault is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    ERC20Upgradeable public token;
    uint256 public burnDelay;

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => Deposit) public deposits;

    event TokensDeposited(address indexed from, uint256 amount, uint256 timestamp);
    event TokensBurned(address indexed admin, uint256 amount);

    /**
     * @dev Initializes the contract with the token to be burned and the burn delay.
     * @param _token The ERC20 token to be burned.
     * @param _burnDelay The delay in seconds before tokens can be burned.
     */
    function initialize(ERC20Upgradeable _token, uint256 _burnDelay) public initializer {
        __AccessControl_init();

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(ADMIN_ROLE, msg.sender);

        token = _token;
        burnDelay = _burnDelay;
    }

    /**
     * @dev Deposits `amount` tokens to the vault.
     * @param amount The amount of tokens to deposit.
     */
    function depositTokens(uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        token.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] = Deposit(amount, block.timestamp);
        emit TokensDeposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @dev Burns tokens from the specified account after the burn delay.
     * Can only be called by an account with the admin role.
     * @param account The account whose tokens to burn.
     */
    function burnTokens(address account) public onlyRole(ADMIN_ROLE) {
        Deposit memory deposit = deposits[account];
        require(deposit.amount > 0, "No tokens to burn");
        require(block.timestamp >= deposit.timestamp + burnDelay, "Burn delay not reached");

        // Cast token to ERC20BurnableUpgradeable before calling burn
        ERC20BurnableUpgradeable(address(token)).burn(deposit.amount);
        delete deposits[account];
        emit TokensBurned(msg.sender, deposit.amount);
    }
}
