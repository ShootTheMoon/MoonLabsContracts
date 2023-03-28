const { ethers, upgrades } = require("hardhat");

async function main() {
  // const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
  // const moonLabsReferral = await upgrades.deployProxy(MoonLabsReferral, {
  //   initializer: "initialize",
  // });
  // await moonLabsReferral.deployed();

  // const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
  // const moonLabsWhitelist = await upgrades.deployProxy(MoonLabsWhitelist, ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "100000000000000000000"], {
  //   initializer: "initialize",
  // });

  // await moonLabsWhitelist.deployed();

  // const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
  // const moonLabsTokenLocker = await upgrades.deployProxy(MoonLabsTokenLocker, ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", moonLabsReferral.address, moonLabsWhitelist.address, "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"], {
  //   initializer: "initialize",
  // });

  // await moonLabsTokenLocker.deployed();

  // const MoonLabsLiquidityLocker = await ethers.getContractFactory("MoonLabsLiquidityLocker");
  // const moonLabsLiquidityLocker = await upgrades.deployProxy(MoonLabsLiquidityLocker, ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", moonLabsReferral.address, moonLabsWhitelist.address, "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"], {
  //   initializer: "initialize",
  // });

  // await moonLabsLiquidityLocker.deployed();

  // const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");
  // const moonLabsVesting = await upgrades.deployProxy(MoonLabsVesting, ["0xaD5D813ab94a32bfF64175C73a1bF49D590bB511", "0xDE5b07E03133e2724684e8700b7D170FEFd6C49D", moonLabsReferral.address, moonLabsWhitelist.address, "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"], {
  //   initializer: "initialize",
  // });

  // await moonLabsVesting.deployed();

  // console.log("Referral contract deployed to:", moonLabsReferral.address);
  // console.log("Whitelist contract deployed to:", moonLabsWhitelist.address);
  // console.log("Token locker contract deployed to:", moonLabsTokenLocker.address);
  // console.log("Liquidity locker contract deployed to:", moonLabsLiquidityLocker.address);
  // console.log("Vesting contract deployed to:", moonLabsVesting.address);

  setTimeout(async () => {
    console.log("Verifying Referral contract...");
    await hre.run("verify:verify", {
      address: "0x3d20e58fc58C103dDF243f0515042c5EEBdd9C71",
    });
    console.log("Done");
  }, 1);

  // setTimeout(async () => {
  //   console.log("Verifying Whitelist contract...");
  //   await hre.run("verify:verify", {
  //     address: "0x471786782D6060208b35A2cB6718e67Cf70d8Fc9",
  //   });
  //   console.log("Done");
  // }, 80000);

  // setTimeout(async () => {
  //   console.log("Verifying Token locker contract...");
  //   await hre.run("verify:verify", {
  //     address: "0xdf7B25e10C2DEC6bbEAb8576791B2895cfAb8BBf",
  //   });
  //   console.log("Done");
  // }, 120000);

  // setTimeout(async () => {
  //   console.log("Verifying Liquidity locker contract...");
  //   await hre.run("verify:verify", {
  //     address: "0x88FBa5BC6f08877Daec408Fba3bf3D76791a8A8A",
  //   });
  //   console.log("Done");
  // }, 180000);

  // setTimeout(async () => {
  //   console.log("Verifying vesting contract...");
  //   await hre.run("verify:verify", {
  //     address: moonLabsVesting.address,
  //   });
  //   console.log("Done");
  // }, 200000);
}

main();
