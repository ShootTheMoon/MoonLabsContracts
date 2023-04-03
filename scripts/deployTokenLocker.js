const { ethers, upgrades } = require("hardhat");

const _mlabToken = "0xa7919d878793A00891Bf742B5E47dcC202a577ce";
const _feeCollector = "0x815D4807f53Fb03dF9F88cEAfa61605CF139b6eb";
const referralAddress = "0x65D71EE0a10552fA13143D809DF2015332c64447";
const whitelistAddress = "0x32B7ef1Ae5aaE189F75A24d561B1872A6B9d1a40";
const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

async function main() {
  const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
  const moonLabsTokenLocker = await upgrades.deployProxy(MoonLabsTokenLocker, [_mlabToken, _feeCollector, referralAddress, whitelistAddress, routerAddress], {
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
