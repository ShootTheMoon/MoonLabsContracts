const { ethers, upgrades } = require("hardhat");

async function main() {
  // const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
  // const moonLabsReferral = await MoonLabsReferral.deploy();

  // const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
  // const moonLabsWhitelist = await MoonLabsWhitelist.deploy("0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "100000000000000000000");

  // const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
  // const moonLabsTokenLocker = await upgrades.deployProxy(
  //   MoonLabsTokenLocker,
  //   ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xab772a83061bc344b3976b3bc4fbbda59d6b5af6", "0x8c3c28941b44e509d6247e59304a43d099264dbd", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"],
  //   {
  //     initializer: "initialize",
  //   }
  // );

  // await moonLabsTokenLocker.deployed();
  // console.log("Referral contract deployed to:", moonLabsReferral.address);
  // console.log("Whitelist contract deployed to:", moonLabsWhitelist.address);
  // console.log("Locker contract deployed to:", moonLabsTokenLocker.address);

  // setTimeout(async () => {
  //   console.log("Verifying Referral contract...");
  //   await hre.run("verify:verify", {
  //     address: "0xab772a83061bc344b3976b3bc4fbbda59d6b5af6",
  //   });
  //   console.log("Done");
  // }, 1);

  // setTimeout(async () => {
  //   console.log("Verifying Whitelist contract...");
  //   await hre.run("verify:verify", {
  //     address: "0x8c3c28941b44e509d6247e59304a43d099264dbd",
  //     constructorArguments: ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "100000000000000000000"],
  //   });
  //   console.log("Done");
  // }, 1);

  setTimeout(async () => {
    console.log("Verifying Locker contract...");
    await hre.run("verify:verify", {
      address: "0x1E5187Ec1A0FE62De508C1153F7e6dF7A8718368",
    });
    console.log("Done");
  }, 1);
}

main();
