import { expect } from 'chai';
import { ethers } from 'hardhat';
import { LinkedMapTest } from '../typechain-types';

describe('LinkedMap', () => {
  let linkedMap: LinkedMapTest;

  beforeEach(async () => {
    // Deploy a test contract that uses the LinkedMap library
    const LinkedMapTest = await ethers.getContractFactory('LinkedMapTest');
    linkedMap = (await LinkedMapTest.deploy()) as unknown as LinkedMapTest;
  });

  describe('Basic Operations', () => {
    it('should start with empty list', async () => {
      expect(await linkedMap.length()).to.equal(0);
      expect(await linkedMap.getHead()).to.equal(ethers.ZeroHash);
      expect(await linkedMap.getTail()).to.equal(ethers.ZeroHash);
    });

    it('should add a single node correctly', async () => {
      const key = ethers.id('test1');
      await linkedMap.add(key);

      expect(await linkedMap.length()).to.equal(1);
      expect(await linkedMap.getHead()).to.equal(key);
      expect(await linkedMap.getTail()).to.equal(key);
      expect(await linkedMap.exists(key)).to.be.true;
    });

    it('should add multiple nodes in correct order', async () => {
      const key1 = ethers.id('test1');
      const key2 = ethers.id('test2');
      const key3 = ethers.id('test3');

      await linkedMap.add(key1);
      await linkedMap.add(key2);
      await linkedMap.add(key3);

      expect(await linkedMap.length()).to.equal(3);
      expect(await linkedMap.getHead()).to.equal(key1);
      expect(await linkedMap.getTail()).to.equal(key3);

      // Check links
      expect(await linkedMap.next(key1)).to.equal(key2);
      expect(await linkedMap.next(key2)).to.equal(key3);
      expect(await linkedMap.next(key3)).to.equal(ethers.ZeroHash);

      expect(await linkedMap.prev(key3)).to.equal(key2);
      expect(await linkedMap.prev(key2)).to.equal(key1);
      expect(await linkedMap.prev(key1)).to.equal(ethers.ZeroHash);
    });

    it('should remove a node correctly', async () => {
      const key1 = ethers.id('test1');
      const key2 = ethers.id('test2');
      const key3 = ethers.id('test3');

      await linkedMap.add(key1);
      await linkedMap.add(key2);
      await linkedMap.add(key3);

      await linkedMap.remove(key2);

      expect(await linkedMap.length()).to.equal(2);
      expect(await linkedMap.exists(key2)).to.be.false;
      expect(await linkedMap.next(key1)).to.equal(key3);
      expect(await linkedMap.prev(key3)).to.equal(key1);
    });
  });

  describe('Edge Cases', () => {
    it('should handle removing head correctly', async () => {
      const key1 = ethers.id('test1');
      const key2 = ethers.id('test2');

      await linkedMap.add(key1);
      await linkedMap.add(key2);

      await linkedMap.remove(key1);

      expect(await linkedMap.getHead()).to.equal(key2);
      expect(await linkedMap.getTail()).to.equal(key2);
      expect(await linkedMap.length()).to.equal(1);
    });

    it('should handle removing tail correctly', async () => {
      const key1 = ethers.id('test1');
      const key2 = ethers.id('test2');

      await linkedMap.add(key1);
      await linkedMap.add(key2);

      await linkedMap.remove(key2);

      expect(await linkedMap.getHead()).to.equal(key1);
      expect(await linkedMap.getTail()).to.equal(key1);
      expect(await linkedMap.length()).to.equal(1);
    });

    it('should revert when adding duplicate key', async () => {
      const key = ethers.id('test1');
      await linkedMap.add(key);

      await expect(linkedMap.add(key))
        .to.be.revertedWithCustomError(linkedMap, 'KeyAlreadyExists')
        .withArgs(key);
    });

    it('should revert when removing non-existent key', async () => {
      const key = ethers.id('test1');

      await expect(linkedMap.remove(key))
        .to.be.revertedWithCustomError(linkedMap, 'KeyDoesNotExist')
        .withArgs(key);
    });
  });

  describe('List Traversal', () => {
    it('should allow forward traversal', async () => {
      const keys = Array(5)
        .fill(0)
        .map((_, i) => ethers.id(`test${i}`));

      // Add all keys
      for (const key of keys) {
        await linkedMap.add(key);
      }

      // Traverse forward
      let current = await linkedMap.getHead();
      for (let i = 0; i < keys.length; i++) {
        expect(current).to.equal(keys[i]);
        current = await linkedMap.next(current);
      }
      expect(current).to.equal(ethers.ZeroHash); // End of list
    });

    it('should allow backward traversal', async () => {
      const keys = Array(5)
        .fill(0)
        .map((_, i) => ethers.id(`test${i}`));

      // Add all keys
      for (const key of keys) {
        await linkedMap.add(key);
      }

      // Traverse backward
      let current = await linkedMap.getTail();
      for (let i = keys.length - 1; i >= 0; i--) {
        expect(current).to.equal(keys[i]);
        current = await linkedMap.prev(current);
      }
      expect(current).to.equal(ethers.ZeroHash); // Start of list
    });
  });
});
