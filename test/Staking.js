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

    //console.log(`deposit `);
    await stakingContract.deposit(toBN(depositamount, 18));
    //console.log(await currentUserInfo());
    await stakingContract.deposit(toBN(SecondDepositAmount, 18));

    await stakingContract.connect(wallet1).deposit(toBN(depositamount, 18));
    await stakingContract.connect(wallet2).deposit(toBN(depositamount, 18));
    var mydeposits = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;

    expect(mydeposits).to.equal(2);
  });

  it("Shouldn't mint 2nd NFT", async function () {
    await expect(NFTtokenContract.safeMint()).to.be.revertedWith(
      "User already owns an NFT"
    );
  });

  it("Should update withdraw wallet correctly", async function () {
    await expect(stakingContract.changeWithdrawalAddress(wallet1.address)).not
      .to.be.reverted;
    expect(
      (await stakingContract.userInfo(owner.address)).WithdrawAddress
    ).to.equal(wallet1.address);
    await expect(stakingContract.changeWithdrawalAddress(owner.address)).not.to
      .be.reverted;
    expect(
      (await stakingContract.userInfo(owner.address)).WithdrawAddress
    ).to.equal(owner.address);
    var useri = await stakingContract.memberDeposit(owner.address, 0);

    expect(Number(useri.amount)).to.equal(
      (1 - DEPOSIT_FEE / 10000) * depositamount * 10 ** 18
    );
  });

  it("Should update fee wallets correctly", async function () {
    await expect(stakingContract.ChangefeeAddress(wallet1.address)).not.to.be
      .reverted;
    expect(await stakingContract.feeWallet()).to.equal(wallet1.address);
    await expect(stakingContract.ChangefeeAddress(owner.address)).not.to.be
      .reverted;
    expect(await stakingContract.feeWallet()).to.equal(owner.address);
  });

  it("Should succesfully change NFT address", async function () {
    await stakingContract.changeNFTcontract(
      global.NFTtokenContract2.address,
      global.NFTtokenContract2.address
    );

    await expect(stakingContract.deposit(toBN(depositamount, 18))).revertedWith(
      "User doesn't own NFT"
    );

    await stakingContract.changeNFTcontract(
      global.NFTtokenContract.address,
      global.NFTtokenContract2.address
    );
  });

  it("Pending Rewards 0 for first 28/59 days", async function () {
    //await increaseTimeBy(Increase27days * oneday);
    //for (var i = 0; i < 27; i++) {
    //console.log(`--------------------------`);
    await increaseTimeBy(27 * oneday);
    /*
       console.log(`i is ${i}`);
        console.log(
        `getweek is ${await Number(await stakingContract.getWeek())}`
      );
      await currentTimeis();
      console.log(
        `getDifferenceFromActionDay is ${await Number(
          await stakingContract.getDifferenceFromActionDay()
        )}`
      );
    }
*/
    var pendingRewards = (await getPending(1, owner.address)).toFixed(0);
    expect((1 * pendingRewards).toFixed(0)).to.equal("0");
    //await increaseTimeBy(Increase29days * oneday);

    await increaseTimeBy(29 * oneday);
  });

  it("Can choose unlock deposit after day 61", async function () {
    await increaseTimeBy((61 - Increase27days - Increase29days - 1) * oneday);

    await expect(stakingContract.UnlockDeposit(0, 1)).not.to.be.reverted;
    useri = await stakingContract.memberDeposit(owner.address, 0);
    expect(Number(useri.amount)).to.equal(
      (1 - DEPOSIT_FEE / 10000) * depositamount * 10 ** 18
    );
    expect(useri.unlocked).to.equal(1);
  });

  it("Can choose withdraw deposit after 61 days", async function () {
    await expect(stakingContract.UnlockDeposit(1, 2)).not.to.be.reverted;
    useri = await stakingContract.memberDeposit(owner.address, 1);
    expect(Number(useri.amount)).to.equal(
      (1 - DEPOSIT_FEE / 10000) * SecondDepositAmount * 10 ** 18
    );
    expect(useri.unlocked).to.equal(2);
  });

  it("can Claim after 70 days", async function () {
    await increaseTimeBy(9 * oneday);

    await stakingContract.connect(wallet1).deposit(toBN(depositamount, 18));
    await stakingContract.connect(wallet2).deposit(toBN(depositamount, 18));
  });

  it("Should Initiate Claim correctly ", async function () {
    await increaseTimeBy(23 * oneday);
    console.log(await stakingContract.getDifferenceFromActionDay());
    await expect(stakingContract.InitiateAction(0, 1)).not.to.be.reverted;
    var depInfo = await stakingContract.memberDeposit(owner.address, 0);
    expect(depInfo.ClaimInitiated).to.equal(1);
    expect(depInfo.WithdrawInitiated).to.equal(0);

    var pendingRewards = (await getPending(0, owner.address)).toFixed(0);
    expect((1 * pendingRewards).toFixed(0)).to.equal(
      (
        depositamount *
        0.95 *
        ((DROP_RATE * 7) / 10000) *
        (1 - DEPOSIT_FEE / 10000)
      ).toFixed(0)
    );
  });

  it("Should fail to initiateUnlock same week", async function () {
    await expect(stakingContract.InitiateAction(0, 2)).revertedWith(
      "Action already initialised"
    );
  });

  it("Should Claim day 118 after deposit, without compounds, correct pending amount", async function () {
    await increaseTimeBy(Increase7days * oneday);

    var TMDBC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;
    pendingbefore = await getPending(0, owner.address);

    await expect(stakingContract.Claim(0)).not.to.be.reverted;

    var TMDAC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;

    var pendingafter = await getPending(0, owner.address);
    expect((1 * pendingbefore).toFixed(0)).to.equal(
      (0.95 * (TMDAC - TMDBC)).toFixed(0)
    );

    expect(pendingafter).to.equal(0);
  });

  it("Compound increase deposits correctly", async function () {
    await increaseTimeBy(1 * oneday);

    await expect(stakingContract.InitiateAction(0, 0)).revertedWith(
      "wrong Initiate day"
    );
    await increaseTimeBy(6 * oneday);

    await stakingContract.connect(wallet1).deposit(toBN(depositamount, 18));
    await stakingContract.connect(wallet2).deposit(toBN(depositamount, 18));
    var depInfo = await stakingContract.memberDeposit(owner.address, 1);
    // console.log(depInfo);
    await expect(stakingContract.InitiateAction(1, 2)).revertedWith(
      "Action already initialised"
    );

    //var userInfo = await stakingContract.userInfo(owner.address);
    var depInfo = await stakingContract.memberDeposit(owner.address, 1);

    expect(depInfo.ClaimInitiated).to.equal(0);
    expect(depInfo.WithdrawInitiated).to.equal(1);

    // await currentDifferenceFromActionDay();
    // console.log(await getPending(1, owner.address));
    //console.log(await stakingContract.toClaim());

    await increaseTimeBy(77 * oneday);
    await expect(stakingContract.Withdraw(1)).not.to.be.reverted;
    //console.log(await getPending(1, owner.address));
    //console.log(await stakingContract.toClaim());

    mydeposits = (await stakingContract.userInfo(owner.address)).NoOfDeposits;

    await increaseTimeBy(7 * oneday);
    // console.log(await stakingContract.memberDeposit(owner.address, 1));

    await expect(stakingContract.InitiateAction(1, 0)).to.be.revertedWith(
      "deposit null"
    );
    //var userInfo = await stakingContract.userInfo(owner.address);
    var depInfo = await stakingContract.memberDeposit(owner.address, 1);

    expect(depInfo.ClaimInitiated).to.equal(0);
    expect(depInfo.WithdrawInitiated).to.equal(0);
    await increaseTimeBy(7 * oneday);

    expect(mydeposits).to.equal(3);
  });

  it("Should Claim day 118 after deposit, with compounds, correct pending amount", async function () {
    await expect(stakingContract.Withdraw(1)).to.be.revertedWith(
      "Withdraw not initiated"
    );

    await stakingContract.connect(wallet1).deposit(toBN(depositamount, 18));
    await stakingContract.connect(wallet2).deposit(toBN(depositamount, 18));
    await stakingContract.deposit(toBN(depositamount, 18));
    await stakingContract.deposit(toBN(depositamount, 18));
    mydeposits = (await stakingContract.userInfo(owner.address)).NoOfDeposits;
    expect(mydeposits).to.equal(5);
    await increaseTimeBy(7 * oneday);
    await increaseTimeBy(70 * oneday);

    await expect(stakingContract.UnlockDeposit(3, 1)).not.to.be.reverted;
    await expect(stakingContract.InitiateAction(3, 0)).not.to.be.reverted;

    //var userInfo = await stakingContract.userInfo(owner.address);
    var depInfo = await stakingContract.memberDeposit(owner.address, 3);

    expect(depInfo.ClaimInitiated).to.equal(0);
    expect(depInfo.WithdrawInitiated).to.equal(0);
    await increaseTimeBy(7 * oneday);
    // await expect(stakingContract.InitiateAction(0)).not.to.be.reverted;

    mydeposits = (await stakingContract.userInfo(owner.address)).NoOfDeposits;

    expect(mydeposits).to.equal(6);
    await increaseTimeBy(7 * oneday);

    await expect(stakingContract.InitiateAction(3, 1)).not.to.be.reverted;
    //var userInfo = await stakingContract.userInfo(owner.address);
    var depInfo = await stakingContract.memberDeposit(owner.address, 3);

    expect(depInfo.ClaimInitiated).to.equal(1);
    expect(depInfo.WithdrawInitiated).to.equal(0);
    await increaseTimeBy(7 * oneday);
    var TMDBC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;
    pendingbefore = await getPending(3, owner.address);

    await expect(stakingContract.Claim(3)).not.to.be.reverted;
    var TMDAC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;

    var pendingafter = await getPending(3, owner.address);
    expect(((1 * pendingbefore) / 0.95).toFixed(0)).to.equal(
      (TMDAC - TMDBC).toFixed(0)
    );
    expect(pendingafter).to.equal(0);
  });

  it("Shouldn't be able to Initiateclaim/InitiateAction(0) after 1 week of initiateUnlock", async function () {
    await expect(stakingContract.InitiateAction(3, 1)).revertedWith(
      "wrong Initiate day"
    );
    await expect(stakingContract.InitiateAction(3, 0)).revertedWith(
      "wrong Initiate day"
    );
  });

  it("Should be able withdraw all funds", async function () {
    var allbal = await USDTContract.balanceOf(stakingContract.address);
    var allbalowner = await USDTContract.balanceOf(
      await stakingContract.feeWallet()
    );

    await expect(stakingContract.getAmount(allbal)).not.to.be.reverted;
    var allbalownerafter = await USDTContract.balanceOf(
      await stakingContract.feeWallet()
    );
    expect(((1 * allbal) / 10 ** 18).toFixed(0)).to.equal(
      ((allbalownerafter - allbalowner) / 10 ** 18).toFixed(0)
    );
    allbal = await USDTContract.balanceOf(stakingContract.address);
    expect(allbal).to.equal(0);
  });

  it("Should be able to deposit after withdrawing all funds", async function () {
    await stakingContract.deposit(toBN(depositamount3, 18));
    await increaseTimeBy(60 * oneday);
    //await expect(stakingContract.UnlockDeposit(2, 1)).not.to.be.reverted;
    // await expect(stakingContract.UnlockDeposit(3, 1)).not.to.be.reverted;
    await expect(stakingContract.UnlockDeposit(4, 1)).not.to.be.reverted;

    await increaseTimeBy(20 * oneday);

    // var pendingRewards = (await getPending(4)).toFixed(0);
    var usertotalDe = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;

    var totalDepLeft = 0;

    for (let i = 0; i < usertotalDe; i++) {
      if (
        (await stakingContract.memberDeposit(owner.address, Number(i)))
          .unlocked == 1
      ) {
        totalDepLeft +=
          (await stakingContract.memberDeposit(owner.address, Number(i)))
            .amount /
          10 ** 18;

        //    console.log(i);
      }
    }

    await increaseTimeBy(11 * oneday);
    //

    await expect(stakingContract.InitiateAction(4, 2)).not.to.be.reverted;

    await increaseTimeBy(55 * oneday);
    //
    var mydepositsBefore = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;
    var depInfo = await stakingContract.memberDeposit(owner.address, 4);
    //console.log(depInfo);
    //console.log((await getPending(4, owner.address)).toFixed(0));
    await expect(stakingContract.Withdraw(4)).not.to.be.reverted;
    var depInfo = await stakingContract.memberDeposit(owner.address, 4);
    //console.log(depInfo);
    await increaseTimeBy(22 * oneday);
    //console.log((await getPending(4, owner.address)).toFixed(0));
    await expect(stakingContract.Withdraw(4)).to.be.revertedWith(
      "Withdraw not initiated"
    );

    var mydepositsAfter = (await stakingContract.userInfo(owner.address))
      .NoOfDeposits;

    // expect(mydepositsAfter - mydepositsBefore).to.equal(1);
    usertotalDe = (await stakingContract.userInfo(owner.address)).NoOfDeposits;
    // console.log(await stakingContract.memberDeposit(owner.address, 6));
    /*
    for (let i = 0; i < usertotalDe; i++) {
      if (true) {
        console.log(
          await stakingContract.memberDeposit(owner.address, 5)
        );
        console.log(i);
      }
    }
    */
  });

  it("Should calculate action modifiers correctly", async function () {
    var increases = [1, 5, 1, 6, 3, 14];

    const initial = Number(await stakingContract.getDifferenceFromActionDay());

    await increaseTimeBy(increases[0] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      initial + increases[0]
    );
    await increaseTimeBy(increases[1] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      initial + increases[0] + increases[1]
    );
    await increaseTimeBy(increases[2] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      getres(initial + increases[0] + increases[1] + increases[2])
    );
    await increaseTimeBy(increases[3] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      getres(
        initial + increases[0] + increases[1] + increases[2] + increases[3]
      )
    );
    await increaseTimeBy(increases[4] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      getres(
        initial +
          increases[0] +
          increases[1] +
          increases[2] +
          increases[3] +
          increases[4]
      )
    );
    await increaseTimeBy(increases[5] * oneday);

    await currentDifferenceFromActionDay();
    expect(await stakingContract.getDifferenceFromActionDay()).to.equal(
      getres(
        initial +
          increases[0] +
          increases[1] +
          increases[2] +
          increases[3] +
          increases[4] +
          increases[5]
      )
    );
  });

  it("Should be able to deposit after withdrawing all funds", async function () {
    await stakingContract.deposit(toBN(depositamount, 18));
    console.log(await stakingContract.memberDeposit(owner.address, 7));

    console.log(await stakingContract.userInfo(owner.address));
    await increaseTimeBy(60 * oneday);
    await expect(stakingContract.UnlockDeposit(7, 2)).not.to.be.reverted;

    console.log(await stakingContract.memberDeposit(owner.address, 7));
    await expect(stakingContract.ChangefeeAddress(wallet1.address)).not.to.be
      .reverted;
    await increaseTimeBy(8 * oneday);
    var TMDBC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;
    pendingbefore = await getPending(7, owner.address);
    await expect(stakingContract.Withdraw(7)).not.to.be.reverted;
    var TMDAC = (await USDTContract.balanceOf(owner.address)) / 10 ** 18;

    var pendingafter = await getPending(7, owner.address);
    console.log(TMDAC, TMDBC, pendingbefore, pendingafter);
    expect((1 * pendingbefore * 0.95).toFixed(0)).to.equal(
      ((TMDAC - TMDBC) * 0.95).toFixed(0)
    );

    expect(pendingafter).to.equal(0);
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
