const { ethers, upgrades } = require("hardhat");

async function main() {
  // WETH address
  const wethAddress = ethers.utils.getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
  const WETH = await ethers.getContractFactory("WETH9");
  const weth = WETH.attach(wethAddress);

  // Uniswap router
  const routerAddress = ethers.utils.getAddress("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
  const Router = await ethers.getContractFactory("UniswapV2Router02");
  const router = Router.attach(routerAddress);

  // Uniswap factory
  const factoryAddress = ethers.utils.getAddress("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  const Factory = await ethers.getContractFactory("UniswapV2Factory");
  const factory = Factory.attach(factoryAddress);

  // Deploy test token
  const TestToken = await ethers.getContractFactory("TestToken");
  const testToken = await TestToken.deploy();

  const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");

  const moonLabsVesting = await upgrades.deployProxy(MoonLabsVesting, ["0x5B38Da6a701c568545dCfcB03FcB875f56beddC4", 30, 100, "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4", 20], {
    initializer: "initialize",
  });

  await moonLabsVesting.deployed();
  console.log("Vesting contract deployed to:", moonLabsVesting.address);
  console.log("Token contract deployed to:", testToken.address);
}

main();
