// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract DepositContract is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct DepositInfo {
        address user;
        uint256 updateTime;
        uint256 depositAmount;
        uint256 ratePerSec; //decimal is 18
        bool isUsed;
    }

    struct UnstakeInfo {
        uint256 timestamp;
        uint256 amount;
        bool isUsed;
    }

    event Deposit( address user, uint256 amount, uint256 rate, uint256 depositTime);
    event Unstaked(address user, uint256 amount, uint256 leftAmount);
    event Withdraw(address user, uint256 amount, uint256 leftAmount);
    event GetReward(address user, uint256 amount, uint256 updateTime);
    event NewDepositRate(uint256 oldRate, uint256 newRate);

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public deposits;
    mapping(address => DepositInfo) public rateinfo;
    mapping(address => UnstakeInfo[]) public unstakeInfo; // user -> unstakeInfo 
    mapping(address => uint256) public unstakeClaimed; // user -> amount

    uint256 public totalDeposit;
    uint256 public totalWithdraw;
    uint256 public totalReward;
    uint256 public rate;

    /// @notice initialize only run once
    function initialize () public initializer {
      __Ownable_init();
      __UUPSUpgradeable_init();
      rate = 20000;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _setDepositRate(uint256 ratio) external onlyOwner {
        uint256 oldRate = rate;
        rate = ratio;
        emit NewDepositRate(oldRate, rate);
    }

    function earn(address user) public view returns (uint256) {
        DepositInfo memory info = rateinfo[user];
        if(info.isUsed)
        {
            uint256 reward = ((block.timestamp - info.updateTime) *
                                info.depositAmount *
                                info.ratePerSec) / 1e18;

            return rewards[msg.sender] + reward;
        }else
            return rewards[msg.sender];
    }

    function deposit() public payable {
        uint256 earned = earn(msg.sender);
        rewards[msg.sender] = earned;

        DepositInfo memory oldInfo = rateinfo[msg.sender];
        uint256 oldDepositAmount = 0;
        if(oldInfo.isUsed)
        {
            oldDepositAmount = oldInfo.depositAmount;
        }

        require(msg.value >= 10 * 1e18 && (msg.value + oldDepositAmount) <= 999 * 1e18, "should between 10 and 999");
        DepositInfo memory newInfo = DepositInfo(
            msg.sender,
            block.timestamp,
            msg.value + oldDepositAmount,
            (rate * 1e18) / 1e5 / (365 * 24 * 60 * 60),
            true
        );
        rateinfo[msg.sender] = newInfo;

        deposits[msg.sender] += msg.value;
        totalDeposit += msg.value;

        emit Deposit(msg.sender, msg.value, rate, block.timestamp);
    }

    function getReward(uint256 amount) public nonReentrant {
        DepositInfo storage info = rateinfo[msg.sender];
        require(info.isUsed == true, "no deposit reward");

        uint256 diff = block.timestamp - info.updateTime;
        uint256 reward = (diff * info.depositAmount * info.ratePerSec) / 1e18;
        info.updateTime = block.timestamp;
        rewards[msg.sender] += reward;

        require(rewards[msg.sender] >= amount, "reward not enough");

        rewards[msg.sender] -= amount;
        totalReward += amount;
        Address.sendValue(payable(msg.sender), amount);

        emit GetReward(msg.sender, amount, block.timestamp);
    }

    function withdraw(uint256 amount) public nonReentrant{
        uint256 leftAmount = 0;
        for(uint i=0; i<unstakeInfo[msg.sender].length; i++)
        {
            UnstakeInfo memory info = unstakeInfo[msg.sender][i];
            if((block.timestamp - info.timestamp) >= 21 * 86400) 
                leftAmount += info.amount;
            else
                leftAmount += info.amount * ((block.timestamp - info.timestamp) / 86400 + 1) / 21;
        }
        leftAmount -= unstakeClaimed[msg.sender];
        require(leftAmount >= amount, "insuficient principal");
        unstakeClaimed[msg.sender] += amount;
        Address.sendValue(payable(msg.sender), amount);
        emit Withdraw(msg.sender, amount, leftAmount-amount);
    }

    function unstake(uint256 amount) public nonReentrant{
        DepositInfo storage info = rateinfo[msg.sender];
        require(info.isUsed == true, "no more deposit reward");
        require(info.depositAmount != 0, "already withdrawn");
        require(info.depositAmount >= amount, "not enough to withdraw");

        uint256 earned = earn(msg.sender);
        rewards[msg.sender] = earned;

        info.updateTime = block.timestamp;
        info.depositAmount -= amount;

        totalDeposit -= amount;
        totalWithdraw += amount;

        UnstakeInfo[] storage infos = unstakeInfo[msg.sender];
        infos.push(UnstakeInfo(block.timestamp, amount, true));

        emit Unstaked(msg.sender, amount, info.depositAmount);
    }
}
