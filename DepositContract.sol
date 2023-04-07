// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "./DepositStorage.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract DepositContract is DepositStorage, ReentrancyGuardUpgradeable {

    event Deposit( address user, uint256 amount, uint256 rate, uint256 depositTime);
    event Unstaked(address user, uint256 amount, uint256 leftAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 leftAmount);
    event GetReward(address user, uint256 amount, uint256 updateTime);
    event NewDepositRate(uint256 oldRate, uint256 newRate);

    constructor () {
        admin = msg.sender;
    }

    receive() external payable {}

    function upgrade(address newImplementation) external {
        require(msg.sender == admin, "only admin authorized");
        implementation = newImplementation;
    }

    function _setDepositRate(uint256 ratio) external {
        require(msg.sender == admin, "only admin authorized");
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

    function unstakeRecordSize(address account) public view returns (uint256) {
        UnstakeInfo[] memory infos = unstakeInfo[account];
        return infos.length;
    }

    function unstakeRecords(address account) public view returns (UnstakeInfo[] memory) {
        UnstakeInfo[] memory infos = unstakeInfo[account];
        return infos;
    }

    function totalUnstakedAmount(address account) public view returns (uint256) {
        UnstakeInfo[] memory infos = unstakeInfo[account];
        uint256 amount = 0;
        for(uint i=0; i<infos.length; i++)
            amount += infos[i].amount;
        return amount;
    }

    function totalUnstakeReleasedAmount(address account) public view returns (uint256) {
        UnstakeInfo[] memory infos = unstakeInfo[account];
        uint256 amount = 0;
        for(uint i=0; i<infos.length; i++)
        {
            if((block.timestamp - infos[i].timestamp) > 21 * 86400)
                amount += infos[i].amount;
        }
        return amount;
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

    // get claimable dynamic principal 
    function getDynamicPrincipal(address account) public view returns(uint256) {
        uint256 leftAmount = 0;
        for(uint i=0; i<unstakeInfo[account].length; i++)
        {
            UnstakeInfo memory info = unstakeInfo[account][i];
            if(info.isClaimed == false) 
                leftAmount += info.amount;
        }
        return leftAmount;
    }

    function unstake(uint256 amount) public nonReentrant{
        DepositInfo storage info = rateinfo[msg.sender];
        require(info.isUsed == true, "no more deposit reward");
        require(amount > 0 && info.depositAmount >= amount, "not enough to withdraw");

        uint256 earned = earn(msg.sender);
        rewards[msg.sender] = earned;

        info.updateTime = block.timestamp;
        info.depositAmount -= amount;
        totalDeposit -= amount;

        UnstakeInfo[] storage infos = unstakeInfo[msg.sender];
        infos.push(UnstakeInfo(block.timestamp, amount, false, true));
        emit Unstaked(msg.sender, amount, info.depositAmount);
    }

    function withdrawById(uint256 id) public nonReentrant{
        require(id < unstakeInfo[msg.sender].length, "invalid unstake id");
        UnstakeInfo storage info = unstakeInfo[msg.sender][id];
        require(info.isUsed, "no unstake record");
        require((block.timestamp - info.timestamp) >= 21 * 86400, "not released within 21 days"); 
        Address.sendValue(payable(msg.sender), info.amount);
        info.isClaimed = true;
        totalWithdraw += info.amount;
        uint256 leftAmount = getDynamicPrincipal(msg.sender);
        emit Withdraw(msg.sender, info.amount, leftAmount);
    }
}
