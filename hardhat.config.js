require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-contract-sizer");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-gas-reporter");
require("hardhat-tracer");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */

module.exports = {
  mocha: {
    timeout: 100000000,
  },
  
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            // Toggles whether the optimizer is on or off.
            // It's good to keep it off for development
            // and turn on for when getting ready to launch.
            enabled: true,
            // The number of runs specifies roughly how often
            // the deployed code will be executed across the
            // life-time of the contract.
            runs: 3000,
          },
        },
      },
    ],

    overrides: {
      "contracts/UniswapV2Router02.sol": {
        version: "0.6.6",
        settings: {},
      },
      "contracts/UniswapV2Factory.sol": {
        version: "0.5.16",
        settings: {},
      },
      "contracts/WETH.sol": {
        version: "0.4.18",
        settings: {},
      },
    },
  },

  networks: {
    hardhat: {
      chainId: 1337,
      forking: {
        url: process.env.MAINNET_API,
        allowUnlimitedContractSize: true,
      },
    },
    mainnet: {
      url: process.env.MAINNET_API,
      accounts: [process.env.PRIVATE_KEY],
    },
    goerli: {
      url: process.env.GOERLI_API,
      accounts: [process.env.PRIVATE_KEY],
    },
    sepolia: {
      url: process.env.SEPOLIA_API,
      accounts: [process.env.PRIVATE_KEY],
    },
    bsc: {
      url: process.env.BSC_API,
      accounts: [process.env.PRIVATE_KEY],
    },
    bsct: {
      url: "https://data-seed-prebsc-2-s3.binance.org:8545/",
      chainId: 97,
      accounts: [process.env.PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: process.env.ETH_SCAN_API,
  },

  gasReporter: {
    enabled: true,
    currency: "USD",
    coinmarketcap: process.env.CMC_API,
  },

  // contractSizer: {
  //   alphaSort: true,
  //   disambiguatePaths: false,
  //   runOnCompile: true,
  //   strict: true,
  // },
};
