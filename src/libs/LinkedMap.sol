// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title LinkedMap
 * @dev Library for managing a doubly linked list with mapping storage.
 */
library LinkedMap {
    struct Node {
        bytes32 prev;
        bytes32 next;
        bool exists;
    }

    struct LinkedList {
        mapping(bytes32 => Node) nodes;
        bytes32 head;
        bytes32 tail;
    }

    /**
     * @dev Adds a new key to the linked list.
     * @param self The linked list storage.
     * @param key The key to add.
     */
    function add(LinkedList storage self, bytes32 key) internal {
        require(!self.nodes[key].exists, "Key already exists");

        Node memory newNode = Node({prev: self.tail, next: bytes32(0), exists: true});

        self.nodes[key] = newNode;

        if (self.tail != bytes32(0)) {
            self.nodes[self.tail].next = key;
        } else {
            self.head = key;
        }

        self.tail = key;
    }

    /**
     * @dev Removes a key from the linked list.
     * @param self The linked list storage.
     * @param key The key to remove.
     */
    function remove(LinkedList storage self, bytes32 key) internal {
        require(self.nodes[key].exists, "Key does not exist");

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
    }

    /**
     * @dev Gets the next key in the linked list.
     * @param self The linked list storage.
     * @param key The current key.
     * @return The next key.
     */
    function next(LinkedList storage self, bytes32 key) internal view returns (bytes32) {
        return self.nodes[key].next;
    }

    /**
     * @dev Gets the previous key in the linked list.
     * @param self The linked list storage.
     * @param key The current key.
     * @return The previous key.
     */
    function prev(LinkedList storage self, bytes32 key) internal view returns (bytes32) {
        return self.nodes[key].prev;
    }

    /**
     * @dev Checks if a key exists in the linked list.
     * @param self The linked list storage.
     * @param key The key to check.
     * @return True if the key exists, false otherwise.
     */
    function exists(LinkedList storage self, bytes32 key) internal view returns (bool) {
        return self.nodes[key].exists;
    }

    /**
     * @dev Gets the head of the linked list.
     * @param self The linked list storage.
     * @return The head key.
     */
    function getHead(LinkedList storage self) internal view returns (bytes32) {
        return self.head;
    }

    /**
     * @dev Gets the tail of the linked list.
     * @param self The linked list storage.
     * @return The tail key.
     */
    function getTail(LinkedList storage self) internal view returns (bytes32) {
        return self.tail;
    }
}
