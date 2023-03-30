const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const deployContracts = require("../testUtils/deployContracts");

function toBN(number, decimal) {
  return (number * 10 ** decimal).toLocaleString("fullwide", {
    useGrouping: false,
  });
}

var oneday = 86400;

var depositamount = 1000;
var DROP_RATE = 0;
var DEPOSIT_FEE = 0;
var WITHDRAW_FEE = 0;
var Increase7days = 7;
var Increase27days = 27;
var Increase29days = 29;
var SecondDepositAmount = 60000;
var depositamount3 = 10000;
describe("Staking contract", function () {
  before(async () => {
    await deployContracts();
    console.log(await stakingContract.getWeek());
    DROP_RATE = await stakingContract.DROP_RATE();
    DEPOSIT_FEE = await stakingContract.depositFeeBP();
    WITHDRAW_FEE = await stakingContract.withdrawFeeBP();
  });

  it("Shouldn't deposit without NFT", async function () {
    await expect(
      stakingContract.deposit(toBN(depositamount, 18))
    ).to.be.revertedWith("User doesn't own NFT");
  });

  it("Should deposit correctly", async function () {
    await NFTtokenContract.connect(wallet1).safeMint();
    await NFTtokenContract.connect(wallet2).safeMint();
    await NFTtokenContract.safeMint();
    console.log(await stakingContract.getDifferenceFromActionDay());
    console.log(await currentTimeis());
    //console.log(`deposit `);
    await stakingContract.deposit(toBN(1 * depositamount, 18));
    await stakingContract.deposit(toBN(2000 * depositamount, 18));
    var mydeposits = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;
    console.log(` my deps after are ${mydeposits}`);

    await increaseTimeBy(60 * oneday);

    await expect(stakingContract.UnlockDeposit(1, 2)).not.to.be.reverted;

    var mydeposits = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;
    console.log(` my deps after unlock are ${mydeposits}`);

    await increaseTimeBy(11 * oneday);

    var depInfo = await stakingContract.memberDeposit(owner.address, 1);
    console.log(depInfo);

    console.log((await stakingContract.getAllrewards()) / 10 ** 18);
    // console.log(await stakingContract.getDifferenceFromActionDay());
    //console.log(await stakingContract.getDifferenceFromActionDay());
    console.log(`---------------------------`);
    console.log((await USDTContract.balanceOf(owner.address)) / 10 ** 18);
    await expect(stakingContract.Withdraw(1)).not.to.be.reverted;
    //await expect(stakingContract.Withdraw(11)).not.to.be.reverted;
    var mydepositsafter = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;
    console.log(`my deps after withdraw are ${mydeposits}`);

    console.log((await USDTContract.balanceOf(owner.address)) / 10 ** 18);
    console.log(0, await stakingContract.memberDeposit(owner.address, 0));
    console.log(1, await stakingContract.memberDeposit(owner.address, 1));
    console.log(2, await stakingContract.memberDeposit(owner.address, 2));
    await increaseTimeBy(44 * oneday);
    //console.log(await stakingContract.getDifferenceFromActionDay());
    await expect(stakingContract.Withdraw(2)).not.to.be.reverted;
    console.log((await stakingContract.getAllrewards()) / 10 ** 18);
    //console.log((await USDTContract.balanceOf(owner.address)) / 10 ** 18);
  });
});
function getres(numb) {
  if (numb > 27) {
    return numb - 28;
  } else if (numb > 13) {
    return numb - 14;
  } else {
    return numb;
  }
}
async function increaseTimeBy(amount) {
  var blockNumBefore = await ethers.provider.getBlockNumber();
  var blockBefore = await ethers.provider.getBlock(blockNumBefore);
  await time.increaseTo(blockBefore.timestamp + amount);
}
async function decreaseTimeBy(amount) {
  var blockNumBefore = await ethers.provider.getBlockNumber();
  var blockBefore = await ethers.provider.getBlock(blockNumBefore);
  await time.increaseTo(blockBefore.timestamp - amount);
  var timestampBefore = blockBefore.timestamp;
  var date = new Date(timestampBefore * 1000);
  // console.log(`time now after increase is ${date}`);
}
async function currentTimeis() {
  var blockNumBefore = await ethers.provider.getBlockNumber();
  var blockBefore = await ethers.provider.getBlock(blockNumBefore);
  var timestampBefore = blockBefore.timestamp;
  var date = new Date(timestampBefore * 1000);
  console.log(`Current time now is ${date}`);
  return date;
}

async function currentTimeisfromTimestamp(ts) {
  var date = new Date(ts * 1000);
  // console.log(date);
  return date;
}
async function getPending(dep, user) {
  var pending = await stakingContract.pendingReward(dep, user);
  return pending / 10 ** 18;
}

async function currentUserInfo() {
  var info = await stakingContract.userInfo(owner.address);

  console.log(info);
}
async function currentDifferenceFromActionDay() {
  var blockNumBefore = await ethers.provider.getBlockNumber();
  var blockBefore = await ethers.provider.getBlock(blockNumBefore);
  var timestampBefore = blockBefore.timestamp;
  var wk = await stakingContract.getWeek();

  var info = await stakingContract.getDifferenceFromActionDay();

  // console.log(timestampBefore, ts, ts / 86400, wk, ad, info);
}
