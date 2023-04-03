const { ethers } = require("hardhat");

const _treasuryWallet = "0xB20f6aa2788f07161370900f3DAc325970b0F766";
const _teamWallet = "0x8a4202907D1d121171F994289416863D1dd0CF2f";
const _liqWallet = "0x815D4807f53Fb03dF9F88cEAfa61605CF139b6eb";
const nftAddress = "0x98d2FAB1A4F340Ae3A1805b21de2992EB5C93b11";

async function main() {
  const MoonLabs = await ethers.getContractFactory("MoonLabs");
  const moonLabs = await MoonLabs.deploy(_treasuryWallet, _teamWallet, _liqWallet, nftAddress);
  await moonLabs.deployed();

  console.log("MLAB token contract deployed to:", moonLabs.address);
  setTimeout(async () => {
    console.log("Verifying MLAB token contract...");
    await hre.run("verify:verify", {
      address: moonLabs.address,
      constructorArguments: [_treasuryWallet, _teamWallet, _liqWallet, nftAddress],
    });
    console.log("Done");
  }, 20000);
}

main();
