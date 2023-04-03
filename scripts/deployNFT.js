const { ethers } = require("hardhat");

async function main() {
  const MoonLabsStakingCards = await ethers.getContractFactory("MoonLabsStakingCards");
  const moonLabsStakingCards = await MoonLabsStakingCards.deploy("Moon Labs Staking Cards", "MLSC", "ipfs://bafybeibbwhzg7hdmrfsl57pwijuepdfusrjfah5ypg2mbv66jyunllsiei\\");
  await moonLabsStakingCards.deployed();

  console.log("MLAB NFT contract deployed to:", moonLabsStakingCards.address);
  
  setTimeout(async () => {
    console.log("Verifying MLAB NFT contract...");
    await hre.run("verify:verify", {
      address: moonLabsStakingCards.address,
      constructorArguments: ["Moon Labs Staking Cards", "MLSC", "ipfs://bafybeibbwhzg7hdmrfsl57pwijuepdfusrjfah5ypg2mbv66jyunllsiei\\"],
    });
    console.log("Done");
  }, 20000);
}

main();
