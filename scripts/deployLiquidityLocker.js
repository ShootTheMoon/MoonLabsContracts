const { ethers, upgrades } = require("hardhat");

const args = require("../values/eth.json");

async function main() {
  const MoonLabsLiquidityLocker = await ethers.getContractFactory("MoonLabsLiquidityLocker");
  const moonLabsLiquidityLocker = await upgrades.deployProxy(MoonLabsLiquidityLocker, [args.mlabToken, args.feeCollector, args.referral, args.whitelist, args.router], {
    initializer: "initialize",
  });
  await moonLabsLiquidityLocker.deployed();

  console.log("Vesting locker contract deployed to:", moonLabsLiquidityLocker.address);

  setTimeout(async () => {
    console.log("Verifying Vesting Locker contract...");
    await hre.run("verify:verify", {
      address: moonLabsLiquidityLocker.address,
    });
    console.log("Done");
  }, 20000);
}

main();
