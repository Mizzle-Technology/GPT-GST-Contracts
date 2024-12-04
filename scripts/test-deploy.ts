import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying contracts with the account:', deployer.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
