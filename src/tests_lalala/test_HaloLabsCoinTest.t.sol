// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import 'forge-std/Test.sol';
import '../src/tokens/HaloLabsCoin.sol';

contract HaloLabsCoinTest is Test {
  HaloLabsCoin token;
  address admin;
  uint256 adminPrivateKey;
  address user = address(2);
  address owner = address(3);

  function setUp() public {
    // admin private key
    adminPrivateKey = uint256(keccak256('user private key'));
    admin = vm.addr(adminPrivateKey);

    token = new HaloLabsCoin();
    // Deploy the contract with the owner as the defualt admin
    vm.prank(owner);
    token.initialize(admin);
  }

  function testInitialize() public view {
    assertEq(token.name(), 'Halo Labs Coin');
    assertEq(token.symbol(), 'HLC');
    assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), owner));
    assertTrue(token.hasRole(token.ADMIN_ROLE(), admin));
  }

  function testInitialSupply() public view {
    assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
  }

  function testMintAmount() public view {
    assertEq(token.balanceOf(address(token)), 1_000_000_000 * 10 ** 18);
  }

  function testDecimals() public view {
    assertEq(token.decimals(), 18);
  }

  function testPause() public {
    vm.prank(admin);
    token.pause();
    assertTrue(token.paused());
  }

  function testUnpause() public {
    vm.prank(admin);
    token.pause();
    assertTrue(token.paused());
    vm.prank(admin);
    token.unpause();
    assertFalse(token.paused());
  }

  function testFailTransferWhilePaused() public {
    vm.prank(admin);
    token.pause();

    vm.prank(admin);
    token.transfer(user, 100);
  }

  function testTransfer() public {
    uint256 amount = 1000 * 10 ** 18;
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        token.DOMAIN_SEPARATOR(),
        keccak256(
          abi.encode(
            keccak256(
              'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
            ),
            admin,
            address(token),
            amount,
            token.nonces(admin),
            deadline
          )
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
    vm.prank(admin);
    token.distribute(user, amount, deadline, v, r, s);
    assertEq(token.balanceOf(user), amount);
  }

  function testGrantRole() public {
    assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), owner));
    bytes32 role = token.ADMIN_ROLE();
    vm.prank(owner);
    token.grantRole(role, user);
    assertTrue(token.hasRole(role, user));
  }

  function testRevokeRole() public {
    bytes32 role = token.ADMIN_ROLE();
    vm.prank(owner);
    token.grantRole(role, user);
    vm.prank(owner);
    token.revokeRole(role, user);
    assertFalse(token.hasRole(role, user));
  }
}
