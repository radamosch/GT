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
var Increase2 = 7;
var Increase3 = 27;
var Increase4 = 29;
var SecondDepositAmount = 3000;
const final = require("../Final.json");
describe("Staking contract", function () {
  before(async () => {
    await deployContracts();
    DROP_RATE = await stakingContract.DROP_RATE();
    DEPOSIT_FEE = await stakingContract.depositFeeBP();
    WITHDRAW_FEE = await stakingContract.withdrawFeeBP();
  });

  it("Shouldn't deposit without NFT", async function () {
    console.log(final.length);
    var lengthis = final.length;
    for (let i = 0; i < lengthis; i++) {
      await stakingContract.createDeposits(
        final[i][1],
        toBN(final[i][2], 18),
        toBN(final[i][5], 18)
      );
    }

    console.log(
      await stakingContract.userInfo(
        "0xA12eDD47aF0C6CAc9ad8DACdd288112485C8D448"
      )
    );
    console.log(
      await stakingContract.userInfo(
        "0xb0FfeF5b5d0cd057d17C49A73FCCf692684495B9"
      )
    );
    console.log(
      await stakingContract.userInfo(
        "0x60930B416CffEFcaE7F76D0830FA2b0fA2285248"
      )
    );
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
async function getPending(dep) {
  var pending = await stakingContract.pendingReward(dep);
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
