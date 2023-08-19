const { ethers, upgrades } = require("hardhat");

const args = require("../values/eth.json");

async function main() {
  const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");
  const moonLabsVesting = await upgrades.deployProxy(MoonLabsVesting,  [args.mlabToken, args.feeCollector, args.referral, args.whitelist, args.router], {
    initializer: "initialize",
  });
  await moonLabsVesting.deployed();

  console.log("Vesting locker contract deployed to:", moonLabsVesting.address);

  setTimeout(async () => {
    console.log("Verifying Vesting Locker contract...");
    await hre.run("verify:verify", {
      address: moonLabsVesting.address,
    });
    console.log("Done");
  }, 20000);
}

main();
