const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers, upgrades } = require("hardhat");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const fs = require("fs");

const pairAbi = JSON.parse(fs.readFileSync("./abis/pairAbi.json"));

describe("Deployment", async function () {
  async function deployTokenFixture() {
    const EPOCH = Math.round(Date.now() / 1000);

    // Contracts are deployed using the first signer/account by default
    const [owner, address1, address2] = await ethers.getSigners();

    // WETH address
    const wethAddress = ethers.utils.getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = WETH.attach(wethAddress);

    // Uniswap router
    const routerAddress = ethers.utils.getAddress("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    const Router = await ethers.getContractFactory("UniswapV2Router02");
    const router = Router.attach(routerAddress);

    // Uniswap factory
    const factoryAddress = ethers.utils.getAddress("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
    const Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = Factory.attach(factoryAddress);

    // Deploy referral contract
    const MoonLabsReferral = await ethers.getContractFactory("MoonLabsReferral");
    const moonLabsReferral = await upgrades.deployProxy(MoonLabsReferral, {
      initializer: "initialize",
    });
    await moonLabsReferral.deployed();

    // Deploy test token
    const TestToken = await ethers.getContractFactory("MoonLabs");
    const testToken = await TestToken.deploy("0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD");

    // Deploy usdc token
    const USDCToken = await ethers.getContractFactory("MoonLabs");
    const usdcToken = await USDCToken.deploy("0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD", "0xD83c60A3c6A88FAff00691F12551Bba2134b7cfD");

    // Deploy whitelist contract
    const MoonLabsWhitelist = await ethers.getContractFactory("MoonLabsWhitelist");
    const moonLabsWhitelist = await upgrades.deployProxy(MoonLabsWhitelist, [testToken.address, owner.address, usdcToken.address, routerAddress, "5000000000"], {
      initializer: "initialize",
    });
    await moonLabsWhitelist.deployed();

    // Deploy token locker contract
    const MoonLabsTokenLocker = await ethers.getContractFactory("MoonLabsTokenLocker");
    const moonLabsTokenLocker = await upgrades.deployProxy(MoonLabsTokenLocker, [testToken.address, address1.address, moonLabsReferral.address, moonLabsWhitelist.address, router.address], {
      initializer: "initialize",
    });
    await moonLabsTokenLocker.deployed();

    // Approve spending for test token
    await testToken.approve(router.address, testToken.balanceOf(owner.address));
    await testToken.approve(moonLabsTokenLocker.address, testToken.balanceOf(owner.address));
    await testToken.approve(moonLabsWhitelist.address, testToken.balanceOf(owner.address));

    // Approve spending for usdc token
    await usdcToken.approve(router.address, usdcToken.balanceOf(owner.address));
    await usdcToken.approve(moonLabsTokenLocker.address, usdcToken.balanceOf(owner.address));
    await usdcToken.approve(moonLabsWhitelist.address, usdcToken.balanceOf(owner.address));

    // Add liquidity to test token
    await router.addLiquidityETH(testToken.address, 2000, 1000, 1, owner.address, EPOCH + 10000, { value: ethers.utils.parseEther(".1") });

    // Add liquidity to usdc token
    await router.addLiquidityETH(usdcToken.address, 2000, 1000, 1, owner.address, EPOCH + 10000, { value: ethers.utils.parseEther(".1") });

    // Get test token pair address
    const pairAddressTest = await factory.getPair(testToken.address, weth.address);
    console.log(pairAddressTest);
    const pairAddressUsdc = await factory.getPair(usdcToken.address, weth.address);
    console.log(pairAddressUsdc);
    // Create test token pair virtual contract
    // const pair = new ethers.Contract(pairAddress, pairAbi, owner);

    moonLabsReferral.addMoonLabsContract(moonLabsTokenLocker.address);

    return { moonLabsTokenLocker, testToken, owner, address1, address2, EPOCH, moonLabsReferral, moonLabsWhitelist, usdcToken };
  }
  describe("Whitelist Contract", async function () {
    it("Should purchase whitelist for token and deduct correct amount of USD", async function () {
      const { owner, moonLabsWhitelist, usdcToken, testToken } = await loadFixture(deployTokenFixture);
      await moonLabsWhitelist.purchaseWhitelist(testToken.address);
    });
  });

  describe("Token Locker Creation", async function () {
    it("Should create 10 TokenLocker instances paying with tokens", async function () {
      const { owner, moonLabsTokenLocker, testToken, address1 } = await loadFixture(deployTokenFixture);

      await expect(moonLabsTokenLocker.createLockPercent(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]]))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 0);
      await expect(moonLabsTokenLocker.createLockPercent(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]]))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 1);
      // expect(await testToken.balanceOf(address1.address)).to.be.equal("100000000000");
    });
    it("Should create 10 TokenLocker instances paying whitelist", async function () {
      const { owner, moonLabsTokenLocker, moonLabsWhitelist, testToken, address1 } = await loadFixture(deployTokenFixture);
      await moonLabsWhitelist.purchaseWhitelist(testToken.address);
      await expect(moonLabsTokenLocker.createLockEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]]))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 0);
      await expect(moonLabsTokenLocker.createLockEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]]))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 1);
      // expect(await testToken.balanceOf(address1.address)).to.be.equal("100000000000");
    });
    it("Should create 10 lock instances paying with Eth", async function () {
      const { owner, address1, address2, moonLabsTokenLocker, testToken } = await loadFixture(deployTokenFixture);

      await expect(moonLabsTokenLocker.createLockEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]], { value: ethers.utils.parseEther(".008") }))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 0);
      await expect(moonLabsTokenLocker.createLockEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, address1.address]], { value: ethers.utils.parseEther(".008") }))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 1);
      // await expect(moonLabsTokenLocker.createLockEth(testToken.address, [[address1.address, 20000000000000, 1672110244, 1672110245]], { value: ethers.utils.parseEther(".1") }))
      //   .to.emit(moonLabsTokenLocker, "LockCreated")
      //   .withArgs(owner.address, testToken.address, 1);
      // await expect(moonLabsTokenLocker.withdrawUnlockedTokens(1, 10000000000000)).to.emit(moonLabsTokenLocker, "TokensWithdrawn").withArgs(owner.address, testToken.address, 1);
      // await expect(moonLabsTokenLocker.withdrawUnlockedTokens(1, 9999999999999)).to.emit(moonLabsTokenLocker, "TokensWithdrawn").withArgs(owner.address, testToken.address, 1);

      // expect(res).to.be.equal([
      //   testToken.address,
      //   owner.address,
      //   ethers.BigNumber.from(20000000000000),
      //   ethers.BigNumber.from(19999999999999),
      //   ethers.BigNumber.from(1672110244),
      //   ethers.BigNumber.from(1672110245),
      //   `tokenAddress: ${testToken.address}`,
      //   `withdrawAddress: ${owner.address}`,
      //   `depositAmount: ${ethers.BigNumber.from(20000000000000)}`,
      //   `withdrawnAmount: ${ethers.BigNumber.from(19999999999999)}`,
      //   `startDate: ${ethers.BigNumber.from(1672110244)}`,
      //   `endDate: ${ethers.BigNumber.from(1672110245)}`,
      // ]);
      // expect(await moonLabsTokenLocker.getClaimableTokens(1)).to.be.equal(1);
      // await expect(moonLabsTokenLocker.withdrawUnlockedTokens(1, 1)).to.emit(moonLabsTokenLocker, "TokensWithdrawn").withArgs(owner.address, testToken.address, 1);
      // expect(await moonLabsTokenLocker.getClaimableTokens(1)).to.be.equal(0);
      // const res = await moonLabsTokenLocker.getInstance(1);
    });
    it("Should create 10 lock instances with referral code paying with Eth", async function () {
      const { owner, address1, moonLabsTokenLocker, testToken, moonLabsReferral } = await loadFixture(deployTokenFixture);
      await moonLabsReferral.addMoonLabsContract(moonLabsTokenLocker.address);
      await moonLabsReferral.createCode("moon");
      expect(await moonLabsReferral.checkIfActive("moon")).to.equal(true);
      await expect(moonLabsTokenLocker.createLockWithCodeEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, owner.address]], "moon", { value: ethers.utils.parseEther(".0072") }))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 0);
      await expect(moonLabsTokenLocker.createLockWithCodeEth(testToken.address, [[20000000000000, 1672110244, 1672110245, owner.address, owner.address]], "moon", { value: ethers.utils.parseEther(".0072") }))
        .to.emit(moonLabsTokenLocker, "LockCreated")
        .withArgs(owner.address, testToken.address, 1, 1);

      await moonLabsTokenLocker.withdrawUnlockedTokens(1, 20000000000000);

      // expect(await moonLabsReferral.getRewardsEarned("moon")).to.equal("20000000000000000");
    });
  });
});
