// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IBEP20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address _owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface myNFT {
    function balanceOf(address) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract Staking is Ownable {
    address public feeWallet;
    address public EmergencyfeeWallet;
    uint256 public depositFeeBP = 1000; //10%
    uint256 public compoundFeeBP = 500; //5%
    uint256 public withdrawFeeBP = 500; //5%
    uint256 public claimLimit = 10000 * 10 ** 18;
    uint256 public withdrawLimit = 50000 * 10 ** 18;
    uint256 public startBlock; // The block number when USDT rewards starts.
    uint256 public DROP_RATE = 60; //0.6 % per day
    uint256 public immutable seconds_per_day = 86400;
    uint256 public immutable Friday = 1678406460; // this is the Friday of initiateAction
    address public NFTaddress; // this is the OG NFT contract address
    address public NFTaddress2; // this is the Whitelist NFT contract address
    //  uint256 public toClaim; // this is the amount that has to be paid out on Friday

    IBEP20 public USDT;
    myNFT NFTContract;
    myNFT NFTContract2;
    mapping(address => UserInfo) public userInfo;

    struct Depo {
        uint256 amount; //deposit amount
        uint256 time; //deposit time
        uint256 lastActionTime; // last time this deposit was claimed/compounded/withdrawn
        uint256 unlocked; // after 60 days users decides to re-lock or not a deposit, 0 means locked, 1 relocked, 2 to withdraw, 3 overLimit withdraw
        uint256 isCompound; // 0 if deposit, 1 if compounded amount
        uint256 WithdrawDate; // The day user is able to withdraw funds
        uint256 WithdrawInitiated; // indicates withdraw initiated
        uint256 ClaimInitiated; // indicates claim initiated
        uint256 lastRewardTimeStamp; // last time user did claim/compound/withdraw
    }

    struct UserInfo {
        Depo[] deposits;
        address WithdrawAddress; //by default msg.sender, can change with changeWithdrawalAddress()
        uint256 NoOfDeposits; // No. of deposits
        uint256 initialDeposit; // Initial deposit, separate cause locked forever
    }

    address[] public UsersInfo;

    event AdminTokenRecovery(address indexed tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UserClaim(address indexed user, uint256 amount);
    event UserCompound(address indexed user, uint256 amount);
    event UserWithdraw(address indexed user, uint256 amount);
    event SetFees(
        uint256 depositFeeBP,
        uint256 withdrawFeeBP,
        uint256 compoundFeeBP
    );

    event ClaimIsInitiated(address indexed user, uint256 unlockDay);
    event CompoundIsInitiated(address indexed user, uint256 unlockDay);
    event WithdrawIsInitiated(address indexed user, uint256 unlockDay);

    constructor(
        address _NFTaddress,
        address _NFTaddress2,
        address _USDTaddress
    ) {
        feeWallet = msg.sender;
        EmergencyfeeWallet = msg.sender;
        USDT = IBEP20(_USDTaddress);
        NFTaddress = _NFTaddress;
        NFTaddress2 = _NFTaddress2;
    }

    modifier hasNFT(address user) {
        require(
            NFTContract.balanceOf(user) != 0 ||
                NFTContract2.balanceOf(user) != 0,
            "User doesn't own NFT"
        );
        _;
    }

    modifier onlyActionDay() {
        require(getDifferenceFromActionDay() >= 7, "Only after 7d");
        _;
    }

    modifier onlyInitiateActionDay() {
        require(getDifferenceFromActionDay() == 0, "wrong Initiate day");
        _;
    }

    modifier hasStarted() {
        require(startBlock != 0, "Not started yet");
        _;
    }

    /**
     * @notice function to initialise Staking.
     */
    function initialize() external onlyOwner {
        require(startBlock == 0, "already initialised");
        startBlock = block.timestamp;
    }

    /**
     * @notice function to change NFT contract addresses.
     */
    function changeNFTcontract(address _NFT, address _NFT2) external onlyOwner {
        require(_NFT != address(0) && _NFT2 != address(0));
        NFTContract = myNFT(_NFT);
        NFTContract2 = myNFT(_NFT2);
    }

    /**
     * @notice function to migrate user deposits
     * @param _user: user address
     * @param _amount: amount ( MINUS depositfee)
     * @param date: date of deposit
     */
    function createDeposits(
        address _user,
        uint256 _amount,
        uint256 date
    ) external payable onlyOwner {
        //  require(startBlock == 0, "Has started ");
        UserInfo storage user = userInfo[_user];

        user.deposits.push(
            Depo({
                amount: _amount, // must remove deposit fee
                time: date,
                lastActionTime: 0,
                unlocked: 0,
                isCompound: 0,
                WithdrawDate: 0,
                WithdrawInitiated: 0,
                ClaimInitiated: 0,
                lastRewardTimeStamp: 0
            })
        );
        user.NoOfDeposits += 1;
    }

    /**
     * @notice function to intiate a deposit.
     * @param _amount: amount of USDT to deposit
     */
    function deposit(uint256 _amount) external hasStarted hasNFT(msg.sender) {
        UserInfo storage user = userInfo[msg.sender];

        uint256 depositFee = (_amount * depositFeeBP) / 10000;

        // only for 1st deposit
        if (user.NoOfDeposits == 0) {
            require(_amount >= 1000 * 10 ** 18, "Minimum deposit is 1000$");
            UsersInfo.push(msg.sender);
            user.initialDeposit += _amount - depositFee;
            user.WithdrawAddress = msg.sender;
        }

        user.deposits.push(
            Depo({
                amount: _amount - depositFee,
                time: block.timestamp,
                lastActionTime: 0,
                unlocked: 0,
                isCompound: 0,
                WithdrawDate: 0,
                WithdrawInitiated: 0,
                ClaimInitiated: 0,
                lastRewardTimeStamp: 0
            })
        );

        USDT.transferFrom(
            address(msg.sender),
            address(this),
            _amount - depositFee
        );

        USDT.transferFrom(address(msg.sender), EmergencyfeeWallet, depositFee);
        user.NoOfDeposits += 1;

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice function to initiate a compound of all eligible deposits.
     * @param _action : 0 is Compound, 1 is Claim, 2 is Withdraw
     */
    function InitiateAction(
        uint256 _deposit,
        uint256 _action
    ) external onlyInitiateActionDay {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];
        require(dep.amount != 0, "deposit null");
        require(block.timestamp > dep.time + 28 days, "warmup period");
        require(
            dep.WithdrawInitiated == 0 &&
                dep.ClaimInitiated == 0 &&
                _action < 3,
            "Action already initialised"
        );
        require(
            block.timestamp > dep.lastRewardTimeStamp + 6 days,
            "already interacted last 6d"
        );

        if (_action == 0) {
            Compound(_deposit);
            emit CompoundIsInitiated(msg.sender, block.timestamp);
        }

        if (_action == 1) {
            dep.ClaimInitiated = 1;
            emit ClaimIsInitiated(msg.sender, block.timestamp);
        }

        if (_action == 2) {
            require(dep.unlocked == 1, "deposit withdrawn");
            require(block.timestamp > dep.time + 60 days, "not yet");
            dep.WithdrawDate = block.timestamp + 6 days;
            dep.WithdrawInitiated = 1;

            emit WithdrawIsInitiated(msg.sender, block.timestamp + 6 days);
        }

        dep.lastRewardTimeStamp = block.timestamp;
    }

    /**
     * @notice function to claim yield from deposits.
     */
    function Claim(
        uint256 _deposit
    ) external onlyActionDay returns (uint256 claimed) {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];
        require(dep.ClaimInitiated == 1, "Claim Not initialised");
        require(
            block.timestamp > dep.lastRewardTimeStamp + 6 days,
            "already interacted last week"
        );

        if (checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)) {
            uint256 period = 7 days;
            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;
            claimed += (period * rewardperblock);
            dep.lastActionTime = block.timestamp;

            uint256 claimFee = (claimed * withdrawFeeBP) / 10000;
            uint256 finalToClaim = claimed - claimFee;

            // max claim is initially 10k USDT, if excess then create new Compounded Deposit
            if (finalToClaim > claimLimit) {
                user.deposits.push(
                    Depo({
                        amount: finalToClaim - claimLimit,
                        time: block.timestamp,
                        lastActionTime: block.timestamp,
                        unlocked: 0,
                        isCompound: 1,
                        WithdrawDate: 0,
                        WithdrawInitiated: 0,
                        ClaimInitiated: 0,
                        lastRewardTimeStamp: 0
                    })
                );
                user.NoOfDeposits += 1;
                finalToClaim = claimLimit;
            }

            //     toClaim -= finalToClaim;
            USDT.transfer(feeWallet, claimFee);
            USDT.transfer(user.WithdrawAddress, finalToClaim);
            dep.lastRewardTimeStamp = block.timestamp;
            dep.ClaimInitiated = 0;

            emit UserClaim(msg.sender, finalToClaim);
            return finalToClaim;
        }
        return 0;
    }

    /**
     * @notice function to compound yield from deposits.
     */
    function Compound(uint256 _deposit) internal {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];

        uint256 pending;
        uint256 compoundFee;

        if (checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)) {
            uint256 period = 7 days; //because min and max are 7

            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;

            pending += (period * rewardperblock);
            dep.lastActionTime = block.timestamp;

            compoundFee = (pending * compoundFeeBP) / 10000;
            uint256 compoundedAmount = pending - compoundFee;

            //all compounds create a new compound
            user.deposits.push(
                Depo({
                    amount: compoundedAmount,
                    time: block.timestamp,
                    lastActionTime: 0,
                    unlocked: 0,
                    isCompound: 1,
                    WithdrawDate: 0,
                    WithdrawInitiated: 0,
                    ClaimInitiated: 0,
                    lastRewardTimeStamp: 0
                })
            );
            USDT.transfer(feeWallet, compoundFee);
            dep.lastRewardTimeStamp = block.timestamp;
            user.NoOfDeposits += 1;
            emit UserCompound(msg.sender, compoundedAmount);
        }
    }

    /**
     * @notice function to withdraw deposits.
     */
    function Withdraw(
        uint256 _deposit
    ) external onlyActionDay returns (uint256 finalAmount, uint256 fee) {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];
        require(dep.WithdrawInitiated == 1, "Withdraw not initiated");
        require(
            dep.WithdrawDate != 0 && dep.WithdrawDate < block.timestamp,
            "Withdraw not yet"
        );

        if (checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)) {
            // user.lastRewardTimeStamp is last time user compounded/claimed

            dep.lastActionTime = block.timestamp;
            finalAmount += dep.amount;
            //initial deposit is non-withdrawable
            if (_deposit == 0) {
                finalAmount -= dep.amount;
            } else {
                dep.amount = 0;
            }

            // max withdraw is initially 50k USDT, if excess (and not previous withdraw [dep.unlocked]<3) then create new Compounded Deposit
            if (finalAmount > withdrawLimit && dep.unlocked < 3) {
                user.deposits.push(
                    Depo({
                        amount: finalAmount - withdrawLimit,
                        time: block.timestamp,
                        lastActionTime: block.timestamp,
                        unlocked: 3,
                        isCompound: 1,
                        WithdrawDate: block.timestamp + 30 days,
                        WithdrawInitiated: 1,
                        ClaimInitiated: 0,
                        lastRewardTimeStamp: 0
                    })
                );

                user.NoOfDeposits += 1;
                finalAmount = withdrawLimit;
            }

            fee = (finalAmount * withdrawFeeBP) / 10000;
            //   toClaim -= (finalAmount - fee);
            USDT.transfer(feeWallet, fee);
            USDT.transfer(user.WithdrawAddress, finalAmount - fee);
            dep.WithdrawInitiated = 0;
            dep.WithdrawDate = 0;
            emit UserWithdraw(msg.sender, finalAmount - fee);
            return (finalAmount, fee);
        }

        return (finalAmount, fee);
    }

    /**
     * @notice function to see if a deposit
     */
    function checkReq(
        uint256 amount,
        uint256 time,
        uint256 unlocked,
        uint256 lastActiontime
    ) internal view returns (bool accepted) {
        // any deposit with deposit.amount != 0 and deposit.time between 29 and  60 days or above 60 days and unlocked
        accepted = (amount != 0 &&
            ((block.timestamp > time + 28 days &&
                block.timestamp < time + 60 days) ||
                (block.timestamp > time + 60 days && unlocked != 0)) &&
            block.timestamp - lastActiontime > 6 days);
    }

    /**
     * @notice function to change withdraw limit
     * @param _withdrawLimit: 50000*10**18 is 50k USDT
     */
    function changeWithdraw_Limit(uint256 _withdrawLimit) external onlyOwner {
        withdrawLimit = _withdrawLimit;
    }

    /**
     * @notice function to change claim limit
     * @param _claimLimit: 10000*10**18 is 10k USDT
     */
    function changeclaim_Limit(uint256 _claimLimit) external onlyOwner {
        claimLimit = _claimLimit;
    }

    /**
     * @notice function to change fees.
     * @param _depositFeeBP,  100 is 1%, 200 is 2% etc
     * * @param _withdrawFeeBP,  100 is 1%, 200 is 2% etc
     * * @param _compoundFeeBP,  100 is 1%, 200 is 2% etc
     */
    function changeFees(
        uint256 _depositFeeBP,
        uint256 _withdrawFeeBP,
        uint256 _compoundFeeBP
    ) external onlyOwner {
        require(
            _depositFeeBP != 0 && _withdrawFeeBP != 0 && _compoundFeeBP != 0,
            "Fees cannot be zero"
        );
        depositFeeBP = _depositFeeBP;
        withdrawFeeBP = _withdrawFeeBP;
        compoundFeeBP = _compoundFeeBP;
        emit SetFees(_depositFeeBP, _withdrawFeeBP, _compoundFeeBP);
    }

    /**
     * @notice function to change withdrawal address.
     * @param _newaddy: address to use as withdarw
     */
    function changeWithdrawalAddress(address _newaddy) external {
        require(_newaddy != address(0), "!nonzero");
        UserInfo storage user = userInfo[msg.sender];
        user.WithdrawAddress = _newaddy;
    }

    /**
     * @notice function to withdraw USDT.
     * @param _amount: amount to withdraw
     */
    function getAmount(uint256 _amount) external onlyOwner {
        USDT.transfer(msg.sender, _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     */
    function recoverTokens(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        IBEP20(_tokenAddress).transfer(address(msg.sender), _tokenAmount);
        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice function to change fee wallet
     */
    function ChangefeeAddress(address _feeWallet) external onlyOwner {
        require(_feeWallet != address(0), "!nonzero");
        feeWallet = _feeWallet;
    }

    /**
     * @notice function to change Emergency fee wallet
     */
    function ChangeEmergencyfeeAddress(
        address _EmergencyfeeWallet
    ) external onlyOwner {
        require(_EmergencyfeeWallet != address(0), "!nonzero");
        EmergencyfeeWallet = _EmergencyfeeWallet;
    }

    /**
     * @notice View function to see week.
     * @return totalweeks : no. of week since start
     */
    function getWeek() public view returns (uint256 totalweeks) {
        return (block.timestamp - Friday) / seconds_per_day / 14;
    }

    /**
     * @notice View function to see day difference between now and ActionDay.
     * @return 0 means you are on ActionDay, 1 means +1 from ActionDay, 2 means +2 etc
     */
    function getDifferenceFromActionDay() public view returns (uint256) {
        uint256 totalsec = (block.timestamp - Friday); //total sec from friday
        return totalsec / seconds_per_day - getWeek() * 14; //7 days in a week
    }

    /**
     * @notice function to decide if user will keep deposit or withdraw
     * @param _depo ; deposit number
     * @param _decision ; 1 = re-lock deposit for yield, 2 = withdraw deposit
     */
    function UnlockDeposit(uint256 _depo, uint256 _decision) external {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_depo];
        require(dep.unlocked == 0, "already decided");
        require(block.timestamp > dep.time + 60 days, "only after 60d");
        require(_decision == 1 || _decision == 2, "bad decision");
        dep.unlocked = _decision;
        if (_decision == 2) {
            dep.WithdrawDate = block.timestamp + 6 days;
            dep.WithdrawInitiated = 1;

            emit WithdrawIsInitiated(msg.sender, block.timestamp + 6 days);
        }
    }

    /**
     * @notice View function to see pending reward for specific deposit on frontend.
     * @return finalAmount Pending reward for a given user/deposit
     */
    function pendingReward(
        uint256 _deposit,
        address _user
    ) public view returns (uint256 finalAmount) {
        UserInfo storage user = userInfo[_user];
        Depo storage dep = user.deposits[_deposit];

        if (dep.ClaimInitiated == 1) {
            uint256 period = 7 days;
            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;
            finalAmount = (period * rewardperblock);
            if (finalAmount > claimLimit) finalAmount = claimLimit;
        } else if (dep.WithdrawInitiated == 1) {
            finalAmount = dep.amount;

            if (finalAmount > withdrawLimit) finalAmount = withdrawLimit;

            if (_deposit == 0) finalAmount -= dep.amount; //initial deposit is non-withdrawable
        }

        finalAmount -= (finalAmount * withdrawFeeBP) / 10000;
    }

    /**
     * @notice View function to see timer to deposit of user deposits.
     * @return time
     */
    function depositCounter(
        address _addr,
        uint256 _deposit,
        uint256 _days
    ) external view returns (uint256 time) {
        UserInfo storage user = userInfo[_addr];
        Depo storage dep = user.deposits[_deposit];

        if (dep.time + _days * 86400 > block.timestamp) {
            return dep.time + _days * 86400 - block.timestamp;
        }
        return 0;
    }

    /**
     * @notice View function to details of user deposits.
     * @return dep : struct Depo
     */
    function memberDeposit(
        address _addr,
        uint256 _deposit
    ) external view returns (Depo memory dep) {
        UserInfo storage user = userInfo[_addr];
        dep = user.deposits[_deposit];
    }

    function getAllrewards() external view returns (uint256 totalUSDT) {
        uint256 lengtharray = UsersInfo.length;
        for (uint256 i; i < lengtharray; ) {
            address currentUser = UsersInfo[i];
            UserInfo storage user = userInfo[currentUser];
            uint256 userDepositNo = user.NoOfDeposits;
            for (uint256 j; j < userDepositNo; ) {
                totalUSDT += pendingReward(j, currentUser);

                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }
}
