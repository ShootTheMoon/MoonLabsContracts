require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.7",
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
        url: "https://eth-mainnet.g.alchemy.com/v2/yDiYga8wtmvav2T5WAxd0yh68bT07gvo",
        allowUnlimitedContractSize: true,
      },
    },
    goerli: {
      url: `${process.env.TESTNET_API}`,
      accounts: ["fe07d0412c3cd1c744d03d913000c11d672f599a33bd9b6687a1d8c8429e1db0"],
    },
  },
  etherscan: {
    apiKey: `${process.env.ETH_SCAN_API}`,
  },
};
