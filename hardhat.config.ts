import type { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import '@typechain/ethers-v6';
import 'solidity-coverage';
import * as dotenv from 'dotenv';

dotenv.config();

if (!process.env.DEFENDER_API_KEY || !process.env.DEFENDER_SECRET_KEY) {
  throw new Error('DEFENDER_API_KEY and DEFENDER_SECRET_KEY must be set');
}

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  typechain: {
    outDir: 'typechain-types',
    target: 'ethers-v6',
    alwaysGenerateOverloads: false,
    externalArtifacts: [],
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    sepolia: {
      url: process.env.SEPOLIA_URL,
      chainId: 11155111,
    },
  },
  defender: {
    apiKey: process.env.DEFENDER_API_KEY,
    apiSecret: process.env.DEFENDER_SECRET_KEY,
  },
};

export default config;
