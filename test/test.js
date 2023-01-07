const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers, upgrades } = require("hardhat");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const fs = require("fs");
const { BigNumber } = require("ethers");

describe("Deployment", async function () {
  async function deployTokenFixture() {
    // Get accounts
    const [owner, address1, address2, address3, address4, address5, address6] = await ethers.getSigners();

    // Deploy nft contract
    const EthPowerups = await ethers.getContractFactory("ETHPowerups");
    const ethPowerups = await EthPowerups.deploy("Powerups", "POWER", " ");

    // Deploy the contract
    const EthFactory = await ethers.getContractFactory("EthFactory");
    const ethFactory = await EthFactory.deploy(address6.address, ethPowerups.address);

    await ethFactory.startFactory({ value: ethers.utils.parseEther("1") });

    // Mint nfts to owner address
    await ethPowerups.pause(false);

    return { owner, address1, address2, address3, address4, address5, address6, ethFactory, ethPowerups };
  }

  describe("Eth Factory Ownership", async function () {
    it("Should transfer ownership", async function () {
      const { address1, ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.transferOwnership(address1.address);
    });

    it("Should renounce ownership", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.renounceOwnership();
    });

    it("Should revert when other than owner tries to transfer ownership", async function () {
      const { ethFactory, address1 } = await loadFixture(deployTokenFixture);

      await expect(ethFactory.connect(address1).transferOwnership(address1.address)).to.be.reverted;
    });

    it("Should revert when other than owner tries to renounce ownership", async function () {
      const { ethFactory, address1 } = await loadFixture(deployTokenFixture);

      await expect(ethFactory.connect(address1).renounceOwnership()).to.be.reverted;
    });
  });

  describe("Eth Factory Owner Only Functions", async function () {
    it("Should set deposit fee", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setDepositFee(1);
      expect(await ethFactory.depositFee()).to.equal(1);
    });

    it("Should set withdraw fee", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setWithdrawFee(1);
      expect(await ethFactory.withdrawFee()).to.equal(1);
    });

    it("Should set referral percent", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setRefPercent(1);
      expect(await ethFactory.refPercent()).to.equal(1);
    });

    it("Should set minimum deposit", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setMinDeposit(1);
      expect(await ethFactory.minDeposit()).to.equal(1);
    });

    it("Should set starting max deposit", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setStartingMax(5);
      expect(await ethFactory.startingMax()).to.equal(5);
    });

    it("Should set max interval", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setMaxInterval(2);
      expect(await ethFactory.maxInterval()).to.equal(2);
    });

    it("Should set step interval", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setStepInterval(1);
      expect(await ethFactory.stepInterval()).to.equal(1);
    });

    it("Should set fee receiver", async function () {
      const { ethFactory, address1 } = await loadFixture(deployTokenFixture);

      await ethFactory.setFeeReceiver(address1.address);
      expect(await ethFactory.feeReceiver()).to.equal(address1.address);
    });

    it("Should set nft multipliers", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setNftMultiplier([1, 2, 3]);
      expect(await ethFactory.nftMultiplier(0)).to.equal(1);
      expect(await ethFactory.nftMultiplier(1)).to.equal(2);
      expect(await ethFactory.nftMultiplier(2)).to.equal(3);
    });

    it("Should set nft tiers", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setNftTiers([100, 200]);
      expect(await ethFactory.nftTiers(0)).to.equal(100);
      expect(await ethFactory.nftTiers(1)).to.equal(200);
    });

    it("Should set max nft multipliers", async function () {
      const { ethFactory } = await loadFixture(deployTokenFixture);

      await ethFactory.setMaxMultipliers(5);
      expect(await ethFactory.maxMultipliers()).to.equal(5);
    });
  });

  describe("Eth Factory Depositing", async function () {
    it("Should revert when deposit does not meet minimum ETH", async function () {
      const { owner, ethFactory } = await loadFixture(deployTokenFixture);
      await expect(ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther(".049") })).to.be.revertedWith("Min deposit");
    });

    it("Should revert when deposit exceeds maximum ETH", async function () {
      const { owner, ethFactory } = await loadFixture(deployTokenFixture);
      await expect(ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("2.001") })).to.be.revertedWith("Max deposit");
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("2") });
      await expect(ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("0.001") })).to.be.revertedWith("Max deposit");
    });

    it("Should not revert when deposit is smaller than minimum but ETH has already been deposited", async function () {
      const { owner, ethFactory } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther(".5") });
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther(".49") });
    });

    for (let i = 1; i < 5; i++) {
      it(`Should not revert when maximum deposit is on step ${i} and deposit is larger than step ${i - 1} maximum deposit - (${i * 25} ETH)`, async function () {
        const { owner, ethFactory } = await loadFixture(deployTokenFixture);
        await owner.sendTransaction({
          to: ethFactory.address,
          value: ethers.utils.parseEther(`${i * 25}`),
        });
        ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther(`${i * 0.5 + 2}`) });
      });
      it(`Should revert when maximum deposit is on step ${i} and deposit is larger than step ${i} maximum deposit - (${i * 25} ETH)`, async function () {
        const { owner, ethFactory } = await loadFixture(deployTokenFixture);
        await owner.sendTransaction({
          to: ethFactory.address,
          value: ethers.utils.parseEther(`${i * 25}`),
        });
        await expect(ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther(`${i * 0.5 + 2.1}`) })).to.be.revertedWith("Max deposit");
      });
    }

    it("Should not revert when maximum deposit is on the final step and deposit is larger than the previous step maximum - (500 ETH)", async function () {
      const { owner, ethFactory } = await loadFixture(deployTokenFixture);
      await owner.sendTransaction({
        to: ethFactory.address,
        value: ethers.utils.parseEther("500"),
      });
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("50") });
    });
  });
  describe("Eth Factory ROI", async function () {
    it("Should return correct ROI 1", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      // advance time by one day and mine a new block
      await helpers.time.increase(86400);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(4147200000);
      await ethPowerups.mint(2);
      await ethFactory.connect(address1).hireWorkers(address2.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(address1.address)).to.equal(0);
      // advance time by one day and mine a new block
      await helpers.time.increase(86400);
      expect(await ethFactory.calcNftMultiplier(address1.address)).to.equal(0);
      expect(await ethFactory.getMyWorkers(address1.address)).to.equal(3071088000);
      expect(await ethFactory.calculateRewards(3071088000)).to.equal("69453198771724936");
    });
    it("Should return correct ROI 2", async function () {
      const { owner, ethFactory, address1 } = await loadFixture(deployTokenFixture);

      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      // advance time by one day and mine a new block
      await helpers.time.increase(86400);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(4147200000);
      expect(await ethFactory.calculateRewards(4147200000)).to.equal("66347117285455087");
    });
  });

  describe("Eth Factory Referral", async function () {
    it("Should map referral address to referral address if user inputs a valid referral address", async function () {
      const { owner, ethFactory, address1, address2 } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(address2.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.referral(owner.address)).to.equal(address2.address);
    });
    it("Should transfer workers to referral address", async function () {
      const { owner, ethFactory, address1 } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(address1.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyMiners(owner.address)).to.equal(48000);
      expect(await ethFactory.getMyWorkers(address1.address)).to.equal(3628800000);
    });
    it("Should send correct amount of referral workers should be sent to referral address", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      let estimatedAmount = await ethFactory.calculateWorkersSimple(ethers.utils.parseEther("1"));
      estimatedAmount = estimatedAmount.toNumber();
      estimatedAmount = estimatedAmount - (estimatedAmount * 4) / 100;
      await ethFactory.hireWorkers(address1.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(address1.address)).to.equal((estimatedAmount * 7) / 100);
    });
    it("Should set referral address to fee address is address entered is msg.sender", async function () {
      const { owner, ethFactory, address1 } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("1") });
      const feeReceiver = await ethFactory.feeReceiver();
      expect(await ethFactory.referral(owner.address)).to.equal(feeReceiver);
    });
  });

  describe("Eth Factory NFT Multipliers", async function () {
    it("Should calculate the correct nft rewards", async function () {
      const { owner, ethFactory, address1, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethPowerups.mint(4);
      await ethFactory.hireWorkers(address1.address, { value: ethers.utils.parseEther("1") });

      let nfts = await ethPowerups.getTokenIds(owner.address);
      let multiplier = 0;
      let amount = 0;
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          if (nfts[i] <= 100) {
            multiplier += 15;
            amount++;
          }
        }
      }
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          if (nfts[i] <= 500) {
            multiplier += 10;
            amount++;
          }
        }
      }
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          multiplier += 5;
          amount++;
        }
      }
      expect(await ethFactory.calcNftMultiplier(owner.address)).to.equal(multiplier);
      await ethPowerups.transferFrom(owner.address, address1.address, nfts[0]);

      nfts = await ethPowerups.getTokenIds(owner.address);
      multiplier = 0;
      amount = 0;
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          if (nfts[i] <= 100) {
            multiplier += 15;
            amount++;
          }
        }
      }
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          if (nfts[i] <= 500) {
            multiplier += 10;
            amount++;
          }
        }
      }
      for (let i = 0; i < nfts.length; i++) {
        if (amount < 2) {
          multiplier += 5;
          amount++;
        }
      }
      expect(await ethFactory.calcNftMultiplier(owner.address)).to.equal(multiplier);
    });
    it("Should not factor in multipliers if nfts are minted after rewards are claimed or workers are rehired", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(address1.address, { value: ethers.utils.parseEther("1") });
      await ethPowerups.mint(4);
      await helpers.time.increase(86400);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(4147248000);
    });
    it("Should factor in multipliers if workers are rehired", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(address1.address, { value: ethers.utils.parseEther(".05") });
      await ethPowerups.mint(4);
      await helpers.time.increase(86400);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(394938971);
      const prevBal = await ethFactory.getMyWorkers(owner.address);
      await ethFactory.claimRewards();
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      await helpers.time.increase(86400);
      const currentBal = await ethFactory.getMyWorkers(owner.address);
      expect(currentBal > prevBal);
    });
  });
  describe("Eth Factory Claiming Workers", async function () {
    it("Should set workers to 0 and claim correct amount of ETH", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      // advance time by one day and mine a new block
      await helpers.time.increase(86400);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(4147200000);
      await ethFactory.calculateRewards(4147200000);
      await ethFactory.claimRewards();
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
    });
    it("Should set workers to 0 and create correct amount of miners", async function () {
      const { owner, ethFactory, address1, address2, ethPowerups } = await loadFixture(deployTokenFixture);
      await ethFactory.hireWorkers(owner.address, { value: ethers.utils.parseEther("1") });
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      // advance time by one day and mine a new block
      await helpers.time.increase(86400);
      const prevBal = await ethFactory.getMyMiners(owner.address);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(4147200000);
      await ethFactory.calculateRewards(4147200000);
      await ethFactory.createMiners(owner.address);
      expect(await ethFactory.getMyWorkers(owner.address)).to.equal(0);
      const currentBal = await ethFactory.getMyMiners(owner.address);
      expect(prevBal.toNumber() + 4147200000 / 1080000).to.equal(currentBal);
    });
  });
});
