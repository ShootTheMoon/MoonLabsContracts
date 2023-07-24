const { ethers, upgrades } = require("hardhat");

const args = require("../values/goerli.json");

async function main() {
  const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
  const moonLabsTokenLocker = await upgrades.deployProxy(MoonLabsTokenLocker, [args.mlabToken, args.feeCollector, args.referral, args.whitelist, args.router], {
    initializer: "initialize",
  });
  await moonLabsTokenLocker.deployed();

  console.log("Token locker contract deployed to:", moonLabsTokenLocker.address);

  setTimeout(async () => {
    console.log("Verifying Token Locker contract...");
    await hre.run("verify:verify", {
      address: moonLabsTokenLocker.address,
    });
    console.log("Done");
  }, 20000);
}

main();
