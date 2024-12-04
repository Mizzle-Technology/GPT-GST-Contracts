// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../utils/Errors.sol';

/**
 * @title LinkedMap
 * @dev Library for managing a doubly linked list with mapping storage.
 */
library LinkedMap {
  // === Events ===
  event NodeAdded(bytes32 indexed key);
  event NodeRemoved(bytes32 indexed key);

  struct Node {
    bytes32 prev;
    bytes32 next;
    bool exists;
  }

  struct LinkedList {
    mapping(bytes32 => Node) nodes;
    bytes32 head;
    bytes32 tail;
    uint256 size;
    uint256[50] __gap; // Storage gap for upgradeable safety
  }

  /**
   * @dev Adds a new key to the linked list.
   * @param self The linked list storage.
   * @param key The key to add.
   * @return success True if the operation was successful.
   */
  function add(LinkedList storage self, bytes32 key) internal returns (bool) {
    require(key != bytes32(0), 'Zero key not allowed');
    require(!self.nodes[key].exists, 'Key already exists');

    Node memory newNode = Node({prev: self.tail, next: bytes32(0), exists: true});

    self.nodes[key] = newNode;

    if (self.tail != bytes32(0)) {
      self.nodes[self.tail].next = key;
    } else {
      self.head = key;
    }

    self.tail = key;
    if (self.size + 1 > type(uint256).max) revert Errors.MaxSizeExceeded();
    self.size++;

    emit NodeAdded(key);
    return true;
  }

  /**
   * @dev Removes a key from the linked list.
   * @param self The linked list storage.
   * @param key The key to remove.
   * @return success True if the operation was successful.
   */
  function remove(LinkedList storage self, bytes32 key) internal returns (bool) {
    require(key != bytes32(0), 'Zero key not allowed');
    require(self.nodes[key].exists, 'Key does not exist');

    Node storage node = self.nodes[key];

    if (node.prev != bytes32(0)) {
      self.nodes[node.prev].next = node.next;
    } else {
      self.head = node.next;
    }

    if (node.next != bytes32(0)) {
      self.nodes[node.next].prev = node.prev;
    } else {
      self.tail = node.prev;
    }

    delete self.nodes[key];
    if (self.size == 0) revert Errors.EmptyList();
    self.size--;

    emit NodeRemoved(key);
    return true;
  }

  /**
   * @dev Gets the next key in the linked list.
   * @param self The linked list storage.
   * @param key The current key.
   * @return bytes32 The next key, or bytes32(0) if at the end.
   */
  function next(LinkedList storage self, bytes32 key) internal view returns (bytes32) {
    return self.nodes[key].next;
  }

  /**
   * @dev Gets the previous key in the linked list.
   * @param self The linked list storage.
   * @param key The current key.
   * @return bytes32 The previous key, or bytes32(0) if at the start.
   */
  function prev(LinkedList storage self, bytes32 key) internal view returns (bytes32) {
    return self.nodes[key].prev;
  }

  /**
   * @dev Checks if a key exists in the linked list.
   * @param self The linked list storage.
   * @param key The key to check.
   * @return bool True if the key exists, false otherwise.
   */
  function exists(LinkedList storage self, bytes32 key) internal view returns (bool) {
    return self.nodes[key].exists;
  }

  /**
   * @dev Gets the head of the linked list.
   * @param self The linked list storage.
   * @return bytes32 The head key, or bytes32(0) if empty.
   */
  function getHead(LinkedList storage self) internal view returns (bytes32) {
    return self.head;
  }

  /**
   * @dev Gets the tail of the linked list.
   * @param self The linked list storage.
   * @return bytes32 The tail key, or bytes32(0) if empty.
   */
  function getTail(LinkedList storage self) internal view returns (bytes32) {
    return self.tail;
  }

  /**
   * @dev Gets the length of the linked list.
   * @param self The linked list storage.
   * @return uint256 The number of nodes in the list.
   */
  function length(LinkedList storage self) internal view returns (uint256) {
    return self.size;
  }
}
