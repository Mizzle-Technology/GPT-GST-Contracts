// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../libs/LinkedMap.sol';

contract LinkedMapTest {
  using LinkedMap for LinkedMap.LinkedList;

  LinkedMap.LinkedList private list;

  function add(bytes32 key) external {
    list.add(key);
  }

  function remove(bytes32 key) external {
    list.remove(key);
  }

  function next(bytes32 key) external view returns (bytes32) {
    return list.next(key);
  }

  function prev(bytes32 key) external view returns (bytes32) {
    return list.prev(key);
  }

  function exists(bytes32 key) external view returns (bool) {
    return list.exists(key);
  }

  function getHead() external view returns (bytes32) {
    return list.getHead();
  }

  function getTail() external view returns (bytes32) {
    return list.getTail();
  }

  function length() external view returns (uint256) {
    return list.length();
  }
}
