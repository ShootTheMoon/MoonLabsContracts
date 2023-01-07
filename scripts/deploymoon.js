const { ethers, upgrades } = require("hardhat");

async function main() {
  // WETH address
  // const wethAddress = ethers.utils.getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
  // const WETH = await ethers.getContractFactory("WETH9");
  // const weth = WETH.attach(wethAddress);

  // Uniswap router
  // const routerAddress = ethers.utils.getAddress("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
  // const Router = await ethers.getContractFactory("UniswapV2Router02");
  // const router = Router.attach(routerAddress);

  // Uniswap factory
  // const factoryAddress = ethers.utils.getAddress("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  // const Factory = await ethers.getContractFactory("UniswapV2Factory");
  // const factory = Factory.attach(factoryAddress);

  // Deploy test token
  // const TestToken = await ethers.getContractFactory("TestToken");
  // const testToken = await TestToken.deploy();

  // const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
  // const moonLabsReferral = await MoonLabsReferral.deploy();

  const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");

  const moonLabsVesting = await upgrades.deployProxy(MoonLabsVesting, ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", 30, 25, "100000000000000000", "0x3bd920C9cc9a40B9C9135e30ece4D3b49710551A", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"], {
    initializer: "initialize",
  });

  await moonLabsVesting.deployed();
  console.log("Vesting contract deployed to:", moonLabsVesting.address);
  // console.log("Referral contract deployed to:", moonLabsReferral.address);
}

main();
