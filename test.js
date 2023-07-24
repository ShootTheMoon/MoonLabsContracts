class taxObj {
  constructor(treasuryTax, teamTax, liquidityTax, burnTax, nftTax) {
    this._treasuryTax = treasuryTax * 10n;
    this._teamTax = teamTax * 10n;
    this._liquidityTax = liquidityTax * 10n;
    this._burnTax = burnTax * 10n;
    this._nftTax = nftTax * 10n;
  }

  get treasuryTax() {
    return this._treasuryTax;
  }

  get teamTax() {
    return this._teamTax;
  }

  get liquidityTax() {
    return this._liquidityTax;
  }

  get burnTax() {
    return this._burnTax;
  }

  get nftTax() {
    return this._nftTax;
  }

  getTotalTax() {
    return this._treasuryTax + this._teamTax + this._liquidityTax + this._burnTax + this._nftTax;
  }
}

const buyTax = new taxObj(0n, 0n, 0n, 0n, 2n);
const sellTax = new taxObj(0n, 0n, 0n, 0n, 2n);

const totalTokenTax = buyTax.getTotalTax() + sellTax.getTotalTax();
const burnTax = buyTax.burnTax + sellTax.burnTax;
const liquidityTax = buyTax.liquidityTax + sellTax.liquidityTax;

const totalSellFee = totalTokenTax - liquidityTax / 2n - burnTax;

const nftBalance = 23120n;

const ethBalance = 100000n;

const tresEth = (ethBalance * (buyTax.treasuryTax + sellTax.treasuryTax)) / totalSellFee;

const teamEth = (ethBalance * (buyTax.teamTax + sellTax.teamTax)) / totalSellFee;

const lpEth = (ethBalance * (buyTax.liquidityTax + sellTax.liquidityTax)) / totalSellFee / 2n;

const nftEth = (ethBalance * (buyTax.nftTax + sellTax.nftTax)) / totalSellFee;

console.log("Treasury Eth:", tresEth);
console.log("Team Eth:", teamEth);
console.log("Nft Eth:", nftEth);
console.log("Liquidity Eth:", lpEth);

console.log(tresEth + teamEth + lpEth + nftEth);
