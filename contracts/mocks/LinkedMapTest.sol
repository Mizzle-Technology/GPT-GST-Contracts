// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../../contracts/libs/LinkedMap.sol';

/**
 * @title LinkedMapTest
 * @notice Test contract for LinkedMap functions
 * @dev Exposes LinkedMap functions for testing purposes
 */
contract LinkedMapTest {
  using LinkedMap for LinkedMap.LinkedList;

  /// @notice Linked list storage
  LinkedMap.LinkedList private list;

  /// @notice Adds a key to the linked list
  function add(bytes32 key) external {
    list.add(key);
  }

  /// @notice Removes a key from the linked list
  function remove(bytes32 key) external {
    list.remove(key);
  }

  /// @notice Gets the next key in the linked list
  function next(bytes32 key) external view returns (bytes32) {
    return list.next(key);
  }

  /// @notice Gets the previous key in the linked list
  function prev(bytes32 key) external view returns (bytes32) {
    return list.prev(key);
  }

  /// @notice Checks if a key exists in the linked list
  function exists(bytes32 key) external view returns (bool) {
    return list.exists(key);
  }

  /// @notice Gets the head key of the linked list
  function getHead() external view returns (bytes32) {
    return list.getHead();
  }

  /// @notice Gets the tail key of the linked list
  function getTail() external view returns (bytes32) {
    return list.getTail();
  }

  /// @notice Gets the length of the linked list
  function length() external view returns (uint256) {
    return list.length();
  }
}
