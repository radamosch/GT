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
var Increase2 = 57;
var Increase3 = 27;
var Increase4 = 29;
var SecondDepositAmount = 3000;
describe("Staking contract", function () {
  before(async () => {
    await deployContracts();
    DROP_RATE = await stakingContract.DROP_RATE();
    DEPOSIT_FEE = await stakingContract.depositFeeBP();
    WITHDRAW_FEE = await stakingContract.withdrawFeeBP();
  });

  it("Should deposit correctly", async function () {
    await NFTtokenContract.safeMint();
    await stakingContract.deposit(toBN(depositamount, 18));
    await stakingContract.deposit(toBN(SecondDepositAmount, 18));
    await increaseTimeBy(3 * oneday);
    console.log(await stakingContract.getDifferenceFromActionDay());
    console.log(await stakingContract.getWeek());
    await expect(stakingContract.Compound(0)).revertedWith(
      "Compound not initialised"
    );
    await increaseTimeBy(Increase2 * oneday);
    await expect(stakingContract.UnlockDeposit(0, 1)).not.to.be.reverted;
    await increaseTimeBy(6 * oneday);
    await currentTimeis();
    await expect(stakingContract.InitiateAction(0, 0)).not.to.be.reverted;
    await increaseTimeBy(6 * oneday);
    await expect(stakingContract.Compound(0)).revertedWith("wrong Action day");
    await increaseTimeBy(1 * oneday);
    await expect(stakingContract.Compound(0)).not.to.be.reverted;
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
async function getPending() {
  var pending = await stakingContract.pendingRewards();
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
  var ad = await stakingContract.ActionDay();
  var info = await stakingContract.getDifferenceFromActionDay();
  var ts = timestampBefore - Number(ad);
  // console.log(timestampBefore, ts, ts / 86400, wk, ad, info);
}
