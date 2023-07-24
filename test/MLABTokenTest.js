const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers, upgrades } = require("hardhat");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const fs = require("fs");

const pairAbi = JSON.parse(fs.readFileSync("./abis/pairAbi.json"));

describe("Deployment", async function () {
  async function deployTokenFixture() {
    const EPOCH = Math.round(Date.now() / 1000);

    // Contracts are deployed using the first signer/account by default
    const [owner, address1, address2, address3, address4] = await ethers.getSigners();

    // WETH address
    const wethAddress = ethers.utils.getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = WETH.attach(wethAddress);

    // Uniswap router
    const routerAddress = ethers.utils.getAddress("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    const Router = await ethers.getContractFactory("UniswapV2Router02");
    const router = Router.attach(routerAddress);

    // NFT
    const MoonLabsStakingCards = await ethers.getContractFactory("MoonLabsStakingCards");
    const moonLabsStakingCards = await MoonLabsStakingCards.deploy("Moon Labs Staking Cards", "MLSC", "ipfs://bafybeibbwhzg7hdmrfsl57pwijuepdfusrjfah5ypg2mbv66jyunllsiei/");
    await moonLabsStakingCards.deployed();

    await moonLabsStakingCards.ownerMint(address2.address, 100);

    // Deploy test token
    const MLABToken = await ethers.getContractFactory("MoonLabs");
    const mlabToken = await MLABToken.deploy(address1.address, address2.address, address3.address, moonLabsStakingCards.address);

    await mlabToken.approve(router.address, mlabToken.balanceOf(owner.address));
    await mlabToken.connect(address1).approve(router.address, mlabToken.balanceOf(owner.address));
    await mlabToken.connect(address4).approve(router.address, mlabToken.balanceOf(owner.address));
    await mlabToken.approve(address4.address, mlabToken.balanceOf(owner.address));

    // Add liquidity to test token
    await router.addLiquidityETH(mlabToken.address, "100000000000000000", "0", "0", owner.address, EPOCH + 10000, { value: ethers.utils.parseEther("1") });
    await mlabToken.launch();

    return { mlabToken, router, weth, owner, address1, address2, address3, address4, EPOCH };
  }

  describe("Swapping Tokens", async function () {
    it("Should swap tokens and take appropriate buy fee", async function () {
      const { mlabToken, router, weth, address4, EPOCH } = await loadFixture(deployTokenFixture);
      await router.connect(address4).swapExactETHForTokensSupportingFeeOnTransferTokens(0, [weth.address, mlabToken.address], address4.address, EPOCH + 1000, { value: ethers.utils.parseEther("1") });

      await router.connect(address4).swapExactTokensForETHSupportingFeeOnTransferTokens("1", 0, [mlabToken.address, weth.address], address4.address, EPOCH + 1000);
      console.log(await mlabToken.nftIndex());
      console.log("NFT Balance", await mlabToken.nftBalance());
      console.log("NFT Payout", await mlabToken.nftPayout());
      console.log("Contract Balance", await ethers.provider.getBalance(mlabToken.address));

      await router.connect(address4).swapExactTokensForETHSupportingFeeOnTransferTokens("1", 0, [mlabToken.address, weth.address], address4.address, EPOCH + 1000);
      console.log(await mlabToken.nftIndex());
      console.log("NFT Balance", await mlabToken.nftBalance());
      console.log("NFT Payout", await mlabToken.nftPayout());
      console.log("Contract Balance", await ethers.provider.getBalance(mlabToken.address));
    });
  });
});
