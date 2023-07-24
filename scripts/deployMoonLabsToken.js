const { ethers } = require("hardhat");

const _treasuryWallet = "0x476655221EF077a12E9BE0c8DA17322C2728aC5B";
const _teamWallet = "0xD91C4Fee7f99A4d25fc57a16177DE3E2642A6df0";
const _liqWallet = "0x454330FE8eE8857DF46ed124Cf00eB26159a3dbb";
const nftAddress = "0xE6FBD188fFc0604E7Aa3290C303C9Dc11ec98D53";

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
