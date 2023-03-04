const { ethers, upgrades } = require("hardhat");

async function main() {
  // const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
  // const moonLabsReferral = await MoonLabsReferral.deploy();

  // await moonLabsReferral.deployed();

  // const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
  // const moonLabsWhitelist = await MoonLabsWhitelist.deploy("0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "100000000000000000000");

  // await moonLabsWhitelist.deployed();

  const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
  const moonLabsTokenLocker = await upgrades.deployProxy(
    MoonLabsTokenLocker,
    ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xD7a2848826776Afc9Ca8Ee449734Fa8B4e4EaAE2", "0xf7350981a3c66c0ba10c8693fecfb39d8f86a970", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"],
    {
      initializer: "initialize",
    }
  );

  await moonLabsTokenLocker.deployed();

  // const MoonLabsLiquidityLocker = await ethers.getContractFactory("MoonLabsLiquidityLocker");
  // const moonLabsLiquidityLocker = await upgrades.deployProxy(
  //   MoonLabsLiquidityLocker,
  //   ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xD7a2848826776Afc9Ca8Ee449734Fa8B4e4EaAE2", "0xf7350981a3c66c0ba10c8693fecfb39d8f86a970", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"],
  //   {
  //     initializer: "initialize",
  //   }
  // );

  // await moonLabsLiquidityLocker.deployed();

  // const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");
  // const moonLabsVesting = await upgrades.deployProxy(
  //   MoonLabsVesting,
  //   ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", "0xD7a2848826776Afc9Ca8Ee449734Fa8B4e4EaAE2", "0xf7350981a3c66c0ba10c8693fecfb39d8f86a970", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"],
  //   {
  //     initializer: "initialize",
  //   }
  // );

  // await moonLabsVesting.deployed();

  // console.log("Referral contract deployed to:", "0xD7a2848826776Afc9Ca8Ee449734Fa8B4e4EaAE2");
  // console.log("Whitelist contract deployed to:", "0xf7350981a3c66c0ba10c8693fecfb39d8f86a970");
  console.log("Token locker contract deployed to:", moonLabsTokenLocker.address);
  // console.log("Liquidity locker contract deployed to:", "0x361Bf74Cd453c4945Eeb17468aeff809F3F844A8");
  // console.log("Vesting contract deployed to:", "0xAbDe1508B297A8a7efEeA413e94b5C3A24Fe0779");

  setTimeout(async () => {
    console.log("Verifying Referral contract...");
    await hre.run("verify:verify", {
      address: moonLabsTokenLocker.address,
    });
    console.log("Done");
  }, 20000);

  // setTimeout(async () => {
  //   console.log("Verifying Whitelist contract...");
  //   await hre.run("verify:verify", {
  //     address: "0xf7350981a3c66c0ba10c8693fecfb39d8f86a970",
  //     constructorArguments: ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "100000000000000000000"],
  //   });
  //   console.log("Done");
  // }, 1);

  // setTimeout(async () => {
  //   console.log("Verifying Token locker contract...");
  //   await hre.run("verify:verify", {
  //     address: "0x15d8ae0b8cfa6ae55d7cfab300c520922c4dab08",
  //   });
  //   console.log("Done");
  // }, 1);

  // setTimeout(async () => {
  //   console.log("Verifying Liquidity locker contract...");
  //   await hre.run("verify:verify", {
  //     address: "0x361Bf74Cd453c4945Eeb17468aeff809F3F844A8",
  //   });
  //   console.log("Done");
  // }, 1);

  // setTimeout(async () => {
  //   console.log("Verifying vesting contract...");
  //   await hre.run("verify:verify", {
  //     address: "0xAbDe1508B297A8a7efEeA413e94b5C3A24Fe0779",
  //   });
  //   console.log("Done");
  // }, 1);
}

main();
