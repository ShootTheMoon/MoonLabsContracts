const { ethers } = require("hardhat");

async function main() {
  // const MoonLabsTestToken = await ethers.getContractFactory("MoonLabs");
  // const moonLabsTestToken = await MoonLabsTestToken.deploy("0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D");

  // await moonLabsTestToken.deployed();

  // const MoonLabsMigrator = await ethers.getContractFactory("MoonLabsMigrator");
  // const moonLabsMigrator = await MoonLabsMigrator.deploy("0xE967574FB976804c6bAC426DFbbcaDE5A18Fdd9B");

  // await moonLabsMigrator.deployed();

  // console.log("Test Token contract deployed to:", moonLabsTestToken.address);
  // console.log("Migrator contract deployed to:", moonLabsMigrator.address);

  // setTimeout(async () => {
  //   console.log("Verifying Test Token contract...");
  //   await hre.run("verify:verify", {
  //     address: moonLabsTestToken.address,
  //     constructorArguments: ["0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D"],
  //   });
  //   console.log("Done");
  // }, 10000);

  setTimeout(async () => {
    console.log("Verifying Migrator contract...");
    await hre.run("verify:verify", {
      address: "0x821545Bb65b2da991919702f6DDd56471FFfA736",
      constructorArguments: ["0xE967574FB976804c6bAC426DFbbcaDE5A18Fdd9B"],
    });
    console.log("Done");
  }, 1);
}

main();
