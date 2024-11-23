// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './ITradingVault.sol';

contract TradingVault is
  Initializable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  ITradingVault
{
  using SafeERC20 for ERC20Upgradeable;

  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  uint256 public constant WITHDRAWAL_DELAY = 1 days;

  // storage gap
  uint256[50] private __gap;

  // withdrawal request struct
  struct WithdrawalRequest {
    address token;
    uint256 amount;
    address transfer_to;
    uint256 expiry;
    uint256 requestTime;
    bool executed;
    bool cancelled;
  }

  address public safeWallet;
  uint256 public WITHDRAWAL_THRESHOLD; // 100k USDC
  mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;

  function initialize(
    address _safeWallet,
    address _admin,
    address _super
  ) public initializer {
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _super);
    _grantRole(ADMIN_ROLE, _admin);
    _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

    require(_safeWallet != address(0), 'Invalid wallet address');
    safeWallet = _safeWallet;
    WITHDRAWAL_THRESHOLD = 100000 * 10 ** 6; // 100k USDC
  }

  // === Queued Withdrawal Functions ===
  /**
   * @notice Queues a withdrawal request for a specified token and amount.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   *      It requires the contract to be not paused and is protected against reentrancy.
   * @param token The address of the token to withdraw.
   * @param amount The amount of the token to withdraw.
   * require The amount must be greater than 0.
   * require The token address must be valid (non-zero address).
   * emit WithdrawalQueued Emitted when a withdrawal request is successfully queued.
   */
  function queueWithdrawal(
    address token,
    uint256 amount
  ) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
    require(amount > 0, 'Amount must be greater than 0');
    require(token != address(0), 'Invalid token address');
    require(IERC20(token).balanceOf(address(this)) >= amount, 'Insufficient balance');
    bytes32 requestId = keccak256(abi.encodePacked(token, amount, block.timestamp));
    require(withdrawalRequests[requestId].amount == 0, 'Duplicate request');

    withdrawalRequests[requestId] = WithdrawalRequest({
      amount: amount,
      token: token,
      transfer_to: safeWallet,
      requestTime: block.timestamp,
      expiry: block.timestamp + WITHDRAWAL_DELAY,
      executed: false,
      cancelled: false
    });

    emit WithdrawalQueued(
      requestId,
      token,
      amount,
      safeWallet,
      block.timestamp,
      block.timestamp + WITHDRAWAL_DELAY
    );
  }

  /**
   * @notice Executes a withdrawal request after verifying all conditions.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function checks if the request ID is valid, the request has not been executed or cancelled,
   * and the required withdrawal delay has passed before marking the request as executed and transferring the tokens.
   * @param requestId The ID of the withdrawal request to be executed.
   * require requestId must be less than the length of withdrawalRequests array.
   * require The request must not have been executed already.
   * require The request must not have been cancelled.
   * require The current block timestamp must be greater than or equal to the request time plus the withdrawal delay.
   * emit WithdrawalExecuted Emitted when a withdrawal request is successfully executed.
   */
  function executeWithdrawal(
    bytes32 requestId
  ) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
    WithdrawalRequest storage request = withdrawalRequests[requestId];
    require(request.amount > 0, 'Invalid request ID');
    require(!request.executed, 'Already executed');
    require(!request.cancelled, 'Request cancelled');
    require(
      block.timestamp >= request.requestTime + WITHDRAWAL_DELAY,
      'Withdrawal delay not met'
    );
    require(
      ERC20Upgradeable(request.token).balanceOf(address(this)) >= request.amount,
      'Insufficient balance'
    );

    ERC20Upgradeable(request.token).safeTransfer(request.transfer_to, request.amount);
    request.executed = true;

    emit WithdrawalExecuted(
      requestId,
      request.token,
      request.amount,
      request.transfer_to,
      block.timestamp
    );
  }

  /**
   * @notice Cancels a withdrawal request.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function checks if the request ID is valid, the request has not been executed or cancelled,
   * and the request has not expired before marking the request as cancelled.
   * @param requestId The ID of the withdrawal request to be cancelled.
   * require requestId must be less than the length of withdrawalRequests array.
   * require The request must not have been executed already.
   * require The request must not have been cancelled already.
   * require The current block timestamp must be less than the request expiry time.
   * emit WithdrawalCancelled Emitted when a withdrawal request is successfully cancelled.
   */
  function cancelWithdrawal(
    bytes32 requestId
  ) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
    WithdrawalRequest storage request = withdrawalRequests[requestId];
    require(request.amount > 0, 'Invalid request ID');
    require(!request.executed, 'Already executed');
    require(!request.cancelled, 'Already cancelled');
    require(block.timestamp < request.expiry, 'Request expired');

    request.cancelled = true;

    emit WithdrawalCancelled(
      requestId,
      request.token,
      request.amount,
      request.transfer_to,
      block.timestamp
    );
  }

  /**
   * @notice Withdraws tokens immediately to the withdrawal wallet.
   * @dev This function can only be called by an account with the ADMIN_ROLE.
   * It ensures that the contract is not paused and uses a non-reentrant guard.
   * The function transfers the specified amount of tokens to the withdrawal wallet.
   * @param token The address of the token to withdraw.
   * @param amount The amount of the token to withdraw.
   * require The amount must be greater than 0.
   * emit ImmediateWithdrawal Emitted when a withdrawal request is successfully executed.
   */
  function withdraw(
    address token,
    uint256 amount
  ) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
    require(amount > 0, 'Amount must be greater than 0');
    require(token != address(0), 'Invalid token address');
    require(safeWallet != address(0), 'Invalid withdrawal wallet address');
    require(amount <= WITHDRAWAL_THRESHOLD, 'Amount exceeds threshold');

    uint256 balance = ERC20Upgradeable(token).balanceOf(address(this));
    require(balance >= amount, 'Insufficient balance');

    ERC20Upgradeable(token).safeTransfer(safeWallet, amount);

    emit ImmediateWithdrawal(token, amount, safeWallet, block.timestamp);
  }

  // === Admin functions ===
  /**
   * @notice Sets the withdrawal wallet address for the trading vault.
   * @dev This function allows the owner to update the wallet address where funds will be withdrawn.
   * @param _safeWallet The address of the new withdrawal wallet.
   * @return success A boolean value indicating whether the wallet address was successfully updated.
   */
  function setWithdrawalWallet(
    address _safeWallet
  ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
    require(_safeWallet != address(0), 'Invalid wallet address');
    require(safeWallet != _safeWallet, 'Same wallet address');
    safeWallet = _safeWallet;
    emit WithdrawalWalletUpdated(_safeWallet);
    return true;
  }

  /**
   * @notice Sets the withdrawal threshold for immediate withdrawals.
   * @dev This function allows the owner to update the threshold amount for immediate withdrawals.
   * @param _threshold The new threshold amount for immediate withdrawals.
   * @return success A boolean value indicating whether the threshold was successfully updated.
   */
  function setWithdrawalThreshold(
    uint256 _threshold
  ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
    require(_threshold > 0, 'Threshold must be greater than 0');
    require(WITHDRAWAL_THRESHOLD != _threshold, 'Same threshold');

    WITHDRAWAL_THRESHOLD = _threshold;

    emit WithdrawalThresholdUpdated(_threshold);
    return true;
  }

  // == Pausable functions ==
  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  // === UUPS Upgrade ===
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
