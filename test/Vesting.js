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
    const moonLabsReferral = await MoonLabsReferral.deploy();

    // Deploy test token
    const TestToken = await ethers.getContractFactory("TestToken");
    const testToken = await TestToken.deploy();

    // Deploy vesting contract
    const MoonLabsVesting = await ethers.getContractFactory("MoonLabsVesting");
    const moonLabsVesting = await upgrades.deployProxy(MoonLabsVesting, [testToken.address, 30, 2, ethers.utils.parseEther(".1"), address1.address, moonLabsReferral.address, router.address], {
      initializer: "initialize",
    });
    await moonLabsVesting.deployed();

    // Approve spending for test token
    await testToken.approve(router.address, testToken.balanceOf(owner.address));
    await testToken.approve(moonLabsVesting.address, testToken.balanceOf(owner.address));

    // Add liquidity to test token
    await router.addLiquidityETH(testToken.address, 2000, 1000, 1, owner.address, EPOCH + 10000, { value: ethers.utils.parseEther(".1") });

    // Get test token pair address
    const pairAddress = await factory.getPair(testToken.address, weth.address);

    //Create test token pair virtual contract
    // const pair = new ethers.Contract(pairAddress, pairAbi, owner);

    return { moonLabsVesting, testToken, owner, address1, address2, EPOCH, moonLabsReferral };
  }
  describe("Ownership", async function () {
    it("Owner should be set", async function () {
      const { owner, moonLabsVesting } = await loadFixture(deployTokenFixture);

      expect(await moonLabsVesting.owner()).to.equal(owner.address);
    });
    it("Transfer ownership should revert if not called by owner", async function () {
      const { address1, moonLabsVesting } = await loadFixture(deployTokenFixture);

      await expect(moonLabsVesting.connect(address1).transferOwnership(address1.address)).to.be.revertedWith("Ownable: caller is not the owner");
    });
    it("Should transfer ownership", async function () {
      const { owner, address1, moonLabsVesting } = await loadFixture(deployTokenFixture);

      await moonLabsVesting.transferOwnership(address1.address);
      expect(await moonLabsVesting.owner()).to.equal(address1.address);
      await moonLabsVesting.connect(address1).transferOwnership(owner.address);
      expect(await moonLabsVesting.owner()).to.equal(owner.address);
    });
  });

  describe("Vesting Creation", async function () {
    it("Should create 10 vesting instances paying with tokens", async function () {
      const { owner, moonLabsVesting, testToken, address1 } = await loadFixture(deployTokenFixture);

      await expect(
        moonLabsVesting.createLockPercent(
          testToken.address,
          [owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address],
          [200, 200, 200, 200, 200, 200, 200, 200, 200, 200],
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          [10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000]
        )
      )
        .to.emit(moonLabsVesting, "LockCreated")
        .withArgs(owner.address, testToken.address, 10);
      expect(await testToken.balanceOf(address1.address)).to.be.equal("4");
    });
    it("Should create 10 vesting instances paying with Eth", async function () {
      const { owner, moonLabsVesting, testToken } = await loadFixture(deployTokenFixture);

      await expect(
        moonLabsVesting.createLockEth(
          testToken.address,
          [owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address],
          [200, 200, 200, 200, 200, 200, 200, 200, 200, 200],
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          [10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000],
          { value: ethers.utils.parseEther("1") }
        )
      )
        .to.emit(moonLabsVesting, "LockCreated")
        .withArgs(owner.address, testToken.address, 10);
    });
    it("Should create 10 vesting instances with referral code paying with Eth", async function () {
      const { owner, moonLabsVesting, testToken, moonLabsReferral } = await loadFixture(deployTokenFixture);
      await moonLabsReferral.addMoonLabsContract(moonLabsVesting.address);
      await moonLabsReferral.createCode("moon");
      expect(await moonLabsReferral.checkIfActive("moon")).to.equal(true);
      await expect(
        moonLabsVesting.createLockWithCodeEth(
          testToken.address,
          [owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address, owner.address],
          [200, 200, 200, 200, 200, 200, 200, 200, 200, 200],
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          [10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000],
          "moon",
          { value: ethers.utils.parseEther(".9") }
        )
      )
        .to.emit(moonLabsVesting, "LockCreated")
        .withArgs(owner.address, testToken.address, 10);

      expect(await moonLabsReferral.getRewardsEarned("moon")).to.equal("100000000000000000");
    });
  });
});
