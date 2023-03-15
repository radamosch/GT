// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.17;
import "./USDT.sol";

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
    uint256 public withdrawLimit = 10000 * 10 ** 18;
    uint256 public startBlock; // The block number when USDT rewards starts.
    uint256 public DROP_RATE = 60; //0.6 % per day
    uint256 public immutable seconds_per_day = 86400;
    uint256 public immutable Friday = 1678406460; // this is the Friday of initiateAction
    address public NFTaddress; // this is the OG NFT contract address
    address public NFTaddress2; // this is the Whitelist NFT contract address
    uint256 public toClaim; // this is the amount that has to be paid out on Friday

    IBEP20 public USDT;
    myNFT NFTContract;
    myNFT NFTContract2;
    mapping(address => UserInfo) public userInfo;

    struct Depo {
        uint256 amount; //deposit amount
        uint256 time; //deposit time
        uint256 lastActionTime; // last time this deposit was claimed/compounded/withdrawn
        uint256 unlocked; // after 60 days users decides to re-lock or not a deposit, 0 means locked, 1 relocked, 2 to withdraw
        uint256 isCompound; // 0 if deposit, 1 if compounded amount
        uint256 WithdrawDate; // The day user is able to withdraw funds
        uint256 WithdrawInitiated; // indicates withdraw initiated
        uint256 ClaimInitiated; // indicates claim initiated
        uint256 CompoundInitiated; // indicates compound initiated
        uint256 lastRewardTimeStamp; // last time user did claim/compound/withdraw
    }

    struct UserInfo {
        Depo[] deposits;
        address WithdrawAddress; //by default msg.sender, can change with changeWithdrawalAddress()
        uint256 NoOfDeposits; // No. of deposits
        uint256 initialDeposit; // Initial deposit, separate cause locked forever
        uint256 NFTId; // the tokenID
    }

    address[] public UsersInfo;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
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
        require(getDifferenceFromActionDay() == 7, "wrong Action day");
        _;
    }

    modifier onlyInitiateActionDay() {
        require(
            getDifferenceFromActionDay() == 0 ||
                getDifferenceFromActionDay() == 13,
            "wrong Initiate day"
        );
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
     * @notice function to change USDT address.
     */
    function changeToken(address _USDTaddress) external onlyOwner {
        require(_USDTaddress != address(0));
        USDT = IBEP20(_USDTaddress);
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
            address myId;
            address UserNFTaddress = NFTContract.balanceOf(msg.sender) != 0
                ? NFTaddress
                : NFTaddress2;

            for (uint256 i; i < 5000; ) {
                myId = myNFT(UserNFTaddress).ownerOf(i);

                if (myId == msg.sender) {
                    user.NFTId = i;
                    i = 5000;
                }
                unchecked {
                    ++i;
                }
            }
        }

        require(
            myNFT(NFTaddress).ownerOf(user.NFTId) == msg.sender ||
                myNFT(NFTaddress2).ownerOf(user.NFTId) == msg.sender,
            "wrong NFT"
        );

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
                CompoundInitiated: 0,
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
        require(dep.amount > 0, "deposit null");
        require(block.timestamp > dep.time + 60 days, "not yet");
        require(dep.unlocked == 1, "deposit withdrawn");
        require(
            dep.WithdrawInitiated == 0 &&
                dep.ClaimInitiated == 0 &&
                dep.CompoundInitiated == 0 &&
                _action < 3,
            "Action already initialised"
        );
        require(
            block.timestamp > dep.lastRewardTimeStamp + 6 days,
            "already interacted last 2 week"
        );

        if (_action == 0) {
            dep.CompoundInitiated = 1;
            emit CompoundIsInitiated(msg.sender, block.timestamp);
        }

        if (_action == 1) {
            dep.ClaimInitiated = 1;
            toClaim += returnAmount(_deposit, msg.sender);
            emit ClaimIsInitiated(msg.sender, block.timestamp);
        }

        if (_action == 2) {
            dep.WithdrawDate = block.timestamp + 60 days;
            dep.WithdrawInitiated = 1;
            toClaim += returnAmount(_deposit, msg.sender);
            emit WithdrawIsInitiated(msg.sender, block.timestamp + 60 days);
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

            uint256 withdrawFee = (claimed * withdrawFeeBP) / 10000;
            toClaim -= claimed;
            USDT.transfer(feeWallet, withdrawFee);
            USDT.transfer(user.WithdrawAddress, claimed - withdrawFee);
            dep.lastRewardTimeStamp = block.timestamp;
            dep.ClaimInitiated = 0;

            emit UserClaim(msg.sender, claimed - withdrawFee);
            return claimed - withdrawFee;
        }
        return 0;
    }

    /**
     * @notice function to compound yield from deposits.
     */
    function Compound(
        uint256 _deposit
    ) external onlyActionDay returns (uint256 compoundedAmount) {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];
        require(dep.CompoundInitiated == 1, "Compound not initialised");
        require(
            block.timestamp > dep.lastRewardTimeStamp + 6 days,
            "already interacted last week"
        );

        uint256 pending;
        uint256 compoundFee;

        if (checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)) {
            // user.lastRewardTimeStamp is last time user compounded/claimed

            uint256 period = 7 days; //because min and max are 7

            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;

            pending += (period * rewardperblock);
            dep.lastActionTime = block.timestamp;

            compoundFee = (pending * compoundFeeBP) / 10000;
            compoundedAmount = pending - compoundFee;
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
                    CompoundInitiated: 0,
                    lastRewardTimeStamp: 0
                })
            );
            USDT.transfer(feeWallet, compoundFee);
            dep.lastRewardTimeStamp = block.timestamp;
            user.NoOfDeposits += 1;
            dep.CompoundInitiated = 0;

            emit UserCompound(msg.sender, compoundedAmount);
            return compoundedAmount;
        }
        return 0;
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

            uint256 period = 7 days; // because min and max are 7

            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;

            dep.lastActionTime = block.timestamp;
            finalAmount += (period * rewardperblock) + dep.amount;
            //initial deposit is non-withdrawable
            if (_deposit == 0) {
                finalAmount -= dep.amount;
            } else {
                dep.amount = 0;
            }

            // max withdraw is initially 10k USDT, if excess then create new Compounded Deposit
            if (finalAmount > withdrawLimit) {
                user.deposits.push(
                    Depo({
                        amount: finalAmount - withdrawLimit,
                        time: block.timestamp,
                        lastActionTime: block.timestamp,
                        unlocked: 0,
                        isCompound: 1,
                        WithdrawDate: 0,
                        WithdrawInitiated: 0,
                        ClaimInitiated: 0,
                        CompoundInitiated: 0,
                        lastRewardTimeStamp: 0
                    })
                );

                user.NoOfDeposits += 1;
                finalAmount = withdrawLimit;
            }

            fee = (finalAmount * withdrawFeeBP) / 10000;
            toClaim -= finalAmount;
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
     * @notice function to change drop rate per day.
     * @param _newRate: rate 6 is 0.6% per day
     */
    function changeDROP_RATE(uint256 _newRate) external onlyOwner {
        DROP_RATE = _newRate;
    }

    function checkReq(
        uint256 amount,
        uint256 time,
        uint256 unlocked,
        uint256 lastActiontime
    ) internal view returns (bool accepted) {
        // any deposit with deposit.amount > 0 and deposit.time between 28 and  60 days or above 60 days and unlocked
        accepted = (amount > 0 &&
            ((block.timestamp > time + 28 days &&
                block.timestamp < time + 60 days) ||
                (block.timestamp > time + 60 days && unlocked == 1)) &&
            // can only do once per 2 weeks
            block.timestamp - lastActiontime > 7 days);
    }

    /**
     * @notice function to change withdraw limit
     * @param _withdrawLimit: 10000*10**18 is 10k USDT
     */
    function changeWithdraw_Limit(uint256 _withdrawLimit) external onlyOwner {
        withdrawLimit = _withdrawLimit;
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
        require(block.timestamp > dep.time + 60 days, "only after 60 days");
        require(_decision == 1 || _decision == 2, "bad decision");
        dep.unlocked = _decision;
        if (_decision == 2) {
            dep.WithdrawDate = block.timestamp + 60 days;
            dep.WithdrawInitiated = 1;
            toClaim += returnAmount(_depo, msg.sender);
            emit WithdrawIsInitiated(msg.sender, block.timestamp + 60 days);
        }
    }

    /**
     * @notice View function to see pending reward for specific deposit on frontend.
     * @return USDTReward Pending reward for a given user/deposit
     */
    function pendingReward(
        uint256 _deposit
    ) public view returns (uint256 USDTReward) {
        UserInfo storage user = userInfo[msg.sender];
        Depo storage dep = user.deposits[_deposit];
        if (checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)) {
            // user.lastRewardTimeStamp is last time user compounded/claimed

            uint256 period = 7 days; // because min and max are 7

            uint256 rewardperblock = (dep.amount * DROP_RATE) /
                seconds_per_day /
                10000;

            USDTReward += (period * rewardperblock);
        }
    }

    /**
     * @notice View function to see return amount for claim or withdraw.
     * @return finalAmount without fees
     */
    function returnAmount(
        uint256 _deposit,
        address _user
    ) public view returns (uint256 finalAmount) {
        UserInfo storage user = userInfo[_user];
        Depo storage dep = user.deposits[_deposit];
        if (dep.CompoundInitiated == 0) {
            // must not be a compound
            if (
                checkReq(dep.amount, dep.time, dep.unlocked, dep.lastActionTime)
            ) {
                uint256 period = 7 days;
                uint256 rewardperblock = (dep.amount * DROP_RATE) /
                    seconds_per_day /
                    10000;

                if (dep.ClaimInitiated == 1) {
                    // if its a claim then don't include capital
                    finalAmount += (period * rewardperblock);
                } else {
                    finalAmount += (period * rewardperblock) + dep.amount;
                    if (_deposit == 0) finalAmount -= dep.amount; //initial deposit is non-withdrawable
                }
            }

            if (finalAmount >= withdrawLimit) {
                // if reward over withdrawLimit then reward = withdrawLimit
                finalAmount = withdrawLimit;
            }

            return (finalAmount);
        }
        return 0;
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
        //return (dep);
    }
}
