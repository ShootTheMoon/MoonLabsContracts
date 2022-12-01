const { ethers, upgrades } = require("hardhat");

const PROXY = "0x458e992368DF3af4960293F440648E1F661fFe22";
async function main() {
  const BoxV2 = await ethers.getContractFactory("BoxV2");
  await upgrades.upgradeProxy(PROXY, BoxV2);

  console.log("Box upgraded");
}

main();
