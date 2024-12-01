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
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '../utils/Errors.sol';

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
  UUPSUpgradeable,
  OwnableUpgradeable
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

  function initialize(address _super, address _admin) public initializer {
    __ERC20_init('Halo Labs Coin', 'HLC');
    __ERC20Capped_init(INITIAL_SUPPLY);
    __ERC20Burnable_init();
    __ERC20Permit_init('Halo Labs Coin');
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __ERC20Pausable_init();
    __Ownable_init(_super);

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    _mint(address(this), INITIAL_SUPPLY);
    emit TokensMinted(address(this), INITIAL_SUPPLY);
  }

  // Override decimals function to return custom decimals
  function decimals() public pure override returns (uint8) {
    return DECIMALS;
  }

  // === Modifiers ===
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Errors.AdminRoleNotGranted(msg.sender);
    }
    _;
  }

  modifier onlyDefaultAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
      revert Errors.DefaultAdminRoleNotGranted(msg.sender);
    }
    _;
  }

  /**
   * @notice Distributes tokens from the contract to a recipient
   * @param recipient The address to receive tokens
   * @param amount The amount of tokens to distribute
   * @param deadline The deadline for the permit signature
   * @param v The v component of the permit signature
   * @param r The r component of the permit signature
   * @param s The s component of the permit signature
   * Requirements:
   * - Only callable by admin
   * - Recipient cannot be zero address
   * - Amount must be > 0 and <= contract balance
   */
  function distribute(
    address recipient,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external whenNotPaused nonReentrant onlyAdmin {
    // Input validation
    if (recipient == address(0)) {
      revert Errors.AddressCannotBeZero();
    }
    if (amount == 0) {
      revert Errors.InvalidAmount(amount);
    }

    uint256 contractBalance = balanceOf(address(this));
    if (contractBalance < amount) {
      revert Errors.InsufficientBalance(contractBalance, amount);
    }

    // Use permit to approve the transfer
    permit(msg.sender, address(this), amount, deadline, v, r, s);

    // Transfer tokens
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
  function _authorizeUpgrade(address newImplementation) internal override onlyDefaultAdmin {}

  // Pause and unpause functions
  function pause() external onlyAdmin {
    _pause();
    emit Paused(msg.sender);
  }

  function unpause() external onlyAdmin {
    _unpause();
    emit Unpaused(msg.sender);
  }
}
