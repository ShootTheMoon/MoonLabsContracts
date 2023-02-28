const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Deployment", async function () {
  async function deployTokenFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, address1, address2, address3] = await ethers.getSigners();

    const OldToken = await ethers.getContractFactory("MoonLabs");
    const oldToken = await OldToken.deploy(address1.address, address2.address, address3.address);

    const Migrator = await ethers.getContractFactory("MoonLabsMigrator");
    const migrator = await Migrator.deploy(oldToken.address);

    oldToken.transfer(address1.address, "1500000000000000");
    oldToken.transfer(address2.address, "1500000000000001");
    oldToken.approve(migrator.address, await oldToken.balanceOf(owner.address));
    oldToken.connect(address1).approve(migrator.address, await oldToken.balanceOf(address1.address));
    oldToken.connect(address2).approve(migrator.address, await oldToken.balanceOf(address2.address));

    return { owner, address1, address2, oldToken, migrator };
  }

  describe("Depositing", async function () {
    it("Should deposit tokens", async function () {
      const { address1, migrator, oldToken } = await loadFixture(deployTokenFixture);

      const sendAmount = await oldToken.balanceOf(address1.address);

      await migrator.connect(address1).depositAllTokens();

      expect(await oldToken.balanceOf(migrator.address)).to.equal(sendAmount);
      expect(await migrator.addressToAmount(address1.address)).to.equal(sendAmount);
    });

    it("Should revert deposit amount exceeds max deposit", async function () {
      const { address2, migrator } = await loadFixture(deployTokenFixture);

      await expect(migrator.connect(address2).depositAllTokens()).to.revertedWith("Max deposit");
    });

    it("Should revert deposit when migrator disabled", async function () {
      const { address1, migrator } = await loadFixture(deployTokenFixture);
      await migrator.disable();
      await expect(migrator.connect(address1).depositAllTokens()).to.revertedWith("Migration not enabled");
    });
  });

  describe("Moderation", async function () {
    it("Should transfer all deposited tokens to owner", async function () {
      const { owner, address1, migrator, oldToken } = await loadFixture(deployTokenFixture);

      const sendAmount = await oldToken.balanceOf(address1.address);
      const balanceBefore = await oldToken.balanceOf(owner.address);

      await migrator.connect(address1).depositAllTokens();

      expect(await oldToken.balanceOf(address1.address)).to.equal(0);

      await migrator.claimDepositedTokens();

      expect(await oldToken.balanceOf(owner.address)).to.equal(sendAmount.add(balanceBefore));
    });

    it("Should revert when other than owner tries to withdraw deposited tokens", async function () {
      const { address1, migrator } = await loadFixture(deployTokenFixture);
      await expect(migrator.connect(address1).claimDepositedTokens()).to.revertedWith("Ownable: caller is not the owner");
    });
  });
});
