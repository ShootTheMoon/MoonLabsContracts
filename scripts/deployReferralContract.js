const { ethers, upgrades } = require("hardhat");

async function main() {
  const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
  const moonLabsReferral = await upgrades.deployProxy(MoonLabsReferral, {
    initializer: "initialize",
  });
  await moonLabsReferral.deployed();

  console.log("Referral contract deployed to:", moonLabsReferral.address);

  setTimeout(async () => {
    console.log("Verifying Referral contract...");
    await hre.run("verify:verify", {
      address: moonLabsReferral.address,
    });
    console.log("Done");
  }, 20000);
}

main();
