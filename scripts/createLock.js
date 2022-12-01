const { ethers, upgrades } = require("hardhat");
async function main() {
  const EPOCH = Math.round(Date.now() / 1000);

  const VestAddr = ethers.utils.getAddress("0xC697f8Dd5aFA871B3fF4a0Cc44Ac8022EE12CBdD");
  const Vest = await ethers.getContractFactory("MoonLabsVesting");
  const vest = Vest.attach(VestAddr);

  await vest.createLock("0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60", ["0x50d02644D84afED8CC03645E09523d903bF8D3bd"], [100], [EPOCH], [EPOCH + 1000], { value: ethers.utils.parseEther(".1") });
}

main();
