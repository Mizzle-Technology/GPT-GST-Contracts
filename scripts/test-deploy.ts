import { ethers, upgrades } from 'hardhat';

async function main() {
  const superAdmin = '0x4822B9eC263ec04897760a81A86dB38ab8806ED5';
  const admin = '0xAE5872C3415887c1C87C745283E0E2b8aE61A62b';
  const sales = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
  const safeWallet = '0xa9C9043Af7C8e81A054365209BF249a2A1fDCA88';

  // === GoldPackToken ===
  const GoldPackTokenFactory = await ethers.getContractFactory('GoldPackToken');
  const goldPackToken = await upgrades.deployProxy(
    GoldPackTokenFactory,
    [superAdmin, admin, sales],
    {
      initializer: 'initialize',
      kind: 'uups',
      useDefenderDeploy: true,
    },
  );

  await goldPackToken.waitForDeployment();
  console.log('GoldPackToken deployed to:', await goldPackToken.getAddress());

  // === TradingVault ===
  const TradingVaultFactory = await ethers.getContractFactory('TradingVault');
  const tradingVault = await upgrades.deployProxy(
    TradingVaultFactory,
    [safeWallet, superAdmin, admin],
    {
      initializer: 'initialize',
      kind: 'uups',
      useDefenderDeploy: true,
    },
  );

  // await tradingVault.waitForDeployment();
  console.log('TradingVault deployed to:', await tradingVault.getAddress());

  // === Sales Contract ===
  const goldPackTokenContract = await goldPackToken.getAddress();
  // Gold price feed address: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
  const goldPriceFeed = '0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea';
  const relayer = '0xcC23C8A7dF47da1BdD43513a648C2B1698576529';
  const tradingVaultContract = await tradingVault.getAddress();

  const SalesContractFactory = await ethers.getContractFactory('SalesContract');
  const salesContract = await upgrades.deployProxy(
    SalesContractFactory,
    [superAdmin, admin, sales, goldPackTokenContract, goldPriceFeed, relayer, tradingVaultContract],
    {
      initializer: 'initialize',
      kind: 'uups',
      useDefenderDeploy: true,
    },
  );

  await salesContract.waitForDeployment();
  console.log('SalesContract deployed to:', await salesContract.getAddress());

  // === BurnVault Contract===
  const BurnVaultFactory = await ethers.getContractFactory('BurnVault');
  const burnVault = await upgrades.deployProxy(BurnVaultFactory, [superAdmin, admin], {
    initializer: 'initialize',
    kind: 'uups',
    useDefenderDeploy: true,
  });

  await burnVault.waitForDeployment();
  console.log('BurnVault deployed to:', await burnVault.getAddress());

  // === Reward Distribution ===
  const RewardDistributionFactory = await ethers.getContractFactory('RewardDistribution');
  const rewardDistribution = await upgrades.deployProxy(
    RewardDistributionFactory,
    [superAdmin, admin],
    {
      initializer: 'initialize',
      kind: 'uups',
      useDefenderDeploy: true,
    },
  );

  await rewardDistribution.waitForDeployment();
  console.log('RewardDistribution deployed to:', await rewardDistribution.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
