const { ethers, upgrades } = require("hardhat");

const _mlabToken = "0xa7919d878793A00891Bf742B5E47dcC202a577ce";
const _feeCollector = "0x815D4807f53Fb03dF9F88cEAfa61605CF139b6eb";
const referralAddress = "0x65D71EE0a10552fA13143D809DF2015332c64447";
const usdAddress = "0x07865c6E87B9F70255377e024ace6630C1Eaa37F";
const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const amountUSDC = "5000000";

async function main() {
  const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
  const moonLabsWhitelist = await upgrades.deployProxy(MoonLabsWhitelist, [_mlabToken, _feeCollector, referralAddress, usdAddress, routerAddress, amountUSDC], {
    initializer: "initialize",
  });
  await moonLabsWhitelist.deployed();

  console.log("Whitelist contract deployed to:", moonLabsWhitelist.address);

  setTimeout(async () => {
    console.log("Verifying Whitelist contract...");
    await hre.run("verify:verify", {
      address: moonLabsWhitelist.address,
    });
    console.log("Done");
  }, 20000);
}

main();
