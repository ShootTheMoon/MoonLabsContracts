const { ethers, upgrades } = require("hardhat");

const args = require("../values/goerli.json");

async function main() {
  const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
  const moonLabsWhitelist = await upgrades.deployProxy(MoonLabsWhitelist, [args.mlabToken, args.feeCollector, args.referral, args.usdAddress, args.router, args.router], {
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
