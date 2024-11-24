// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Core functionality
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol';

/**
 * @title MizzleTechToken
 * @dev This contract represents the MizzleTechToken, which is an ERC20 token implementation.
 * The contract includes functionalities for token creation, transfer, and other standard ERC20 operations.
 */
contract HaloLabsCoin is
  ERC20CappedUpgradeable,
  ERC20BurnableUpgradeable,
  ERC20PermitUpgradeable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  ERC20PausableUpgradeable,
  UUPSUpgradeable
{
  // Admin role
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
  uint8 public constant DECIMALS = 18;

  //private
  uint256[50] private __gap;

  // Events
  event TokensMinted(address indexed to, uint256 amount);
  event TokensDistributed(address indexed to, uint256 amount);

  function initialize(address admin) public initializer {
    __ERC20_init('Halo Labs Coin', 'HLC');
    __ERC20Capped_init(INITIAL_SUPPLY);
    __ERC20Burnable_init();
    __ERC20Permit_init('Halo Labs Coin');
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();
    __ERC20Pausable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    _mint(address(this), INITIAL_SUPPLY);
    emit TokensMinted(address(this), INITIAL_SUPPLY);
  }

  // Override decimals function to return custom decimals
  function decimals() public pure override returns (uint8) {
    return DECIMALS;
  }

  function distribute(
    address recipient,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external onlyRole(ADMIN_ROLE) {
    // Use permit to approve the transfer
    permit(msg.sender, address(this), amount, deadline, v, r, s);
    // check if the recipient is not the zero address
    require(recipient != address(0), 'MizzleTechToken: recipient is the zero address');
    // check if the amount is not zero
    require(amount > 0, 'MizzleTechToken: amount is zero');
    // check if the amount is not greater than the balance of the contract
    require(balanceOf(address(this)) >= amount, 'MizzleTechToken: insufficient balance');

    _transfer(address(this), recipient, amount);
    emit TokensDistributed(recipient, amount);
  }

  // Override the _update function to resolve inheritance conflict
  function _update(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20Upgradeable, ERC20CappedUpgradeable, ERC20PausableUpgradeable) {
    super._update(from, to, amount);
  }

  // Authorize upgrade function required by UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

  // Pause and unpause functions
  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
    emit Paused(msg.sender);
  }

  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
    emit Unpaused(msg.sender);
  }
}
