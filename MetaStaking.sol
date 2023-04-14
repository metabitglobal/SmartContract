// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "./StakingStorage.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// main node -> light node -> user
contract MetaStaking is StakingStorage, ReentrancyGuardUpgradeable {

    event NewUser(address indexed user, uint256 lightId, uint256 mainId, address referee, uint256 timestamp);
    event Staked( address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 rate, uint256 timestamp);
    event Unstaked(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 leftAmount, uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount, uint256 leftAmount);
    event RewardClaimed(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 timestamp);
    event NewStakeRate(uint256 nodeId, uint256 oldRate, uint256 newRate);
    event NewMainNodeCommission(uint256 nodeId, uint256 oldRate, uint256 rate);
    event NewLightNodeCommission(uint256 nodeId, uint256 oldRate, uint256 rate);
    event NewMainNode(uint256 id, uint256 timestamp);
    event NewLightNode(uint256 id, uint256 mainId, address owner, uint256 timestamp);
    event ReferRewardSet(uint256 batchNo);
    event ReStaked(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 reward, uint256 timestamp);

    constructor () {
        admin = msg.sender;
    }

    function upgrade(address newImplementation) external {
        require(msg.sender == admin, "only admin authorized");
        implementation = newImplementation;
    }

    function _setInitTime(uint256 timestamp) external {
        require(msg.sender == admin, "only admin authorized");
        initTime = timestamp;
    }

    function _setStopLimit(uint256 limit) external  {
        require(msg.sender == admin, "only admin authorized");
        stopLimit = limit;
    }

    function _setMainNodeStakeCapacity(uint256 cap) external  {
        require(msg.sender == admin, "only admin authorized");
        mainNodeCap = cap;
    }

    function _setMainNodeStakeRate(uint256 id, uint256 ratio) external  {
        require(msg.sender == admin, "only admin authorized");
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node does not exists.");
        uint256 oldRate = node.rate;
        node.rate = ratio;
        emit NewStakeRate(id, oldRate, node.rate);
    }

    function _setMainNodeCommissionRate(uint256 id, uint256 rate) external  {
        require(msg.sender == admin, "only admin authorized");
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node does not exists.");
        uint256 oldRate = node.commissionRate;
        node.commissionRate = rate;
        emit NewMainNodeCommission(id, oldRate, rate);
    }

    function _setLightNodeCommissionRate(uint256 id, uint256 rate) external {
        require(rate <= 500, "ratio must be lower than 5%");
        require(ownerLightNodeId[msg.sender] == id, "only owner of light node authorized");
        LightNodeInfo storage node = lightNodeInfo[id];
        require(node.isUsed, "light node does not exists.");
        uint256 oldRate = node.commissionRate;
        node.commissionRate = rate;
        emit NewLightNodeCommission(id, oldRate, rate);
    }

    function _initMainNode(uint256 num) external  returns (uint256[] memory) {
        require(msg.sender == admin, "only admin authorized");
        uint256[] memory ids = new uint256[](num);
        for(uint256 i = currentMainNodeIndex; i < currentMainNodeIndex + num; i++)
        {
            MainNodeInfo memory node = MainNodeInfo(0, 0, 0, 0, 0, DEFAULT_RATE, 500, false, true);
            mainNodeInfo[i] = node;
            ids[i-currentMainNodeIndex] = i;
            emit NewMainNode(i, block.timestamp);
        }
        currentMainNodeIndex += num;
        return ids;
    }

    // update nodes info related
    function updateNodesInfo(address account, uint256 amount) internal {
        StakeInfo storage info = stakeInfo[account];
        require(info.isUsed, "invalid account");
        info.rewardAmount += amount;
        info.totalRewardAmount += amount;
        uint256 lightNodeId = info.lightNodeId;
        LightNodeInfo storage lightNode = lightNodeInfo[lightNodeId];
        require(lightNode.isUsed, "invalid light node");
        lightNode.rewardAmount += amount;
        lightNode.totalRewardAmount += amount;

        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        require(mainNode.isUsed, "invalid main node");
        mainNode.rewardAmount += amount;
        mainNode.totalRewardAmount += amount;

        currentTotalReward += amount;
        totalReward += amount;
    }

    function _setReferReward(uint256 batchNo, address[] calldata accounts, uint256[] calldata values) external  {
        require(msg.sender == admin, "only admin authorized");
        require(batchNo != 0, "batchNo cannot be empty");
        require(accounts.length == values.length, "length not match");
        
        uint256 key = block.timestamp / SECONDS_PER_DAY;
        for(uint i=0; i<accounts.length; i++)
        {
            if(firstDynamicRecord[accounts[i]] == 0)
                firstDynamicRecord[accounts[i]] = key;
            dynamicReward[key][accounts[i]] += values[i];
            updateNodesInfo(accounts[i], values[i]);
        }
        emit ReferRewardSet(batchNo);
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
    // get claimable dynamic reward
    function getDynamicReward(address account) public view returns(uint256) {
        uint256 day = block.timestamp / SECONDS_PER_DAY;
        uint256 firstDate = firstDynamicRecord[account];
        if(firstDate == 0)
            return 0;

        uint256 totalDynamicReward = 0;
        for(uint i = 0; i < 100; i++)
        {
            uint256 key = day - i;
            if(key < firstDate)
                break;
            totalDynamicReward += dynamicReward[key][account]*(i+1)/100;
        }
        uint256 k = day - 100;
        while(k >= firstDate)
        {
            totalDynamicReward += dynamicReward[k][account];
            k--;
        }
        return totalDynamicReward;
    }

    function registerLightNode(uint256 id, address account, address referee, uint256 rate) external  returns(uint256) {
        require(msg.sender == admin, "only admin authorized");
        require(!lightNodeBlacklist[account], "account has a lightnode already");
        require(rate <= 500, "ratio must be lower than 500");
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node not exist");

        if(referee != address(0))
        {
            StakeInfo memory refereeUser = stakeInfo[referee];
            require(refereeUser.isUsed, "referee not exist");
        }
        node.totalLightNodes += 1;
        LightNodeInfo memory lightNode = LightNodeInfo(id, 0, 0, 0, 0, 0, block.timestamp, rate, account, false, true);
        uint256 lightNodeId = currentLightNodeIndex;
        lightNodeInfo[lightNodeId] = lightNode;
        ownerLightNodeId[account] = lightNodeId;
        currentLightNodeIndex += 1;
        emit NewLightNode(lightNodeId, id, account, block.timestamp);

        // register a new user
        StakeInfo storage info = stakeInfo[account];
        require(!info.isUsed, "has been registered");
        StakeInfo memory newInfo = StakeInfo(
            lightNodeId,
            block.timestamp,
            0,
            0,
            0,
            0,
            0,
            referee,
            true
        );
        stakeInfo[account] = newInfo;
        LightNodeInfo storage lnode = lightNodeInfo[lightNodeId];
        lnode.totalUsers += 1;
        lightNodeBlacklist[account] = true;
        emit NewUser(account, lightNodeId, id, referee, block.timestamp);

        return lightNodeId;
    }

    function reward(address account) public view returns (uint256) {
        StakeInfo memory info = stakeInfo[account];
        if(info.isUsed)
        {
            return info.totalRewardAmount - dynamicRewardClaimed[account];
        }else
            return 0;
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

    // register a new user 
    function registerUser(address referee) public {

        require(referee != address(0), "referee is invalid");
        StakeInfo storage info = stakeInfo[msg.sender];
        require(!info.isUsed, "has been registered");
        
        uint256 lightNodeId = ownerLightNodeId[referee];
        if(lightNodeId == 0)
        {
            StakeInfo memory referInfo = stakeInfo[referee];
            lightNodeId = referInfo.lightNodeId;
        }
        require(lightNodeId > 0, "invalid light node id");

        StakeInfo memory newInfo = StakeInfo(
            lightNodeId,
            block.timestamp,
            0,
            0,
            0,
            0,
            0,
            referee,
            true
        );
        stakeInfo[msg.sender] = newInfo;

        LightNodeInfo storage lightNode = lightNodeInfo[lightNodeId];
        require(lightNode.isUsed, "invalid light node id");
        lightNode.totalUsers += 1;
        uint256 mainNodeId = lightNode.mainNodeId;

        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        require(mainNode.isUsed, "invalid main node");

        emit NewUser(msg.sender, lightNodeId, mainNodeId, referee, block.timestamp);
    }

    // stake from light nodes
    function stake() public payable {

        require(block.timestamp >= initTime, "staking not started");

        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "user not registered");
        require(info.lightNodeId != 0, "light node id not match");

        uint256 rate = DEFAULT_RATE;
        uint256 mainNodeId = 0;
        info.stakeAmount += msg.value;
        info.totalStakeAmount += msg.value;
        info.updateTime = block.timestamp;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        require(lightNode.isUsed && !lightNode.isStopped, "light node stopped");
        lightNode.stakeAmount += msg.value;
        lightNode.totalStakeAmount += msg.value;
        mainNodeId = lightNode.mainNodeId;
        
        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        require(mainNode.isUsed && !mainNode.isStopped, "main node stopped");
        require(msg.value + mainNode.stakeAmount <= mainNodeCap, "exceeds main node capacity");
        mainNode.stakeAmount += msg.value;
        mainNode.totalStakeAmount += msg.value;
        currentTotalStaked += msg.value;
        totalStaked += msg.value;

        emit Staked(msg.sender, info.lightNodeId, mainNodeId, msg.value, rate, block.timestamp);
    }

    // restake
    function restake() public {

        require(block.timestamp >= initTime, "staking not started");

        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake record");
        uint256 dReward = getDynamicReward(msg.sender);
        uint256 amount = dReward - dynamicRewardClaimed[msg.sender];
        dynamicRewardClaimed[msg.sender] = dReward;

        info.rewardAmount -= amount;
        info.stakeAmount += amount;
        info.totalStakeAmount += amount;
        info.updateTime = block.timestamp;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        require(lightNode.isUsed && !lightNode.isStopped, "light node stopped");
        lightNode.rewardAmount -= amount;
        lightNode.stakeAmount += amount;
        lightNode.totalStakeAmount += amount;
        uint256 mainNodeId = lightNode.mainNodeId;
        
        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        require(mainNode.isUsed && !mainNode.isStopped, "main node stopped");
        require(amount + mainNode.stakeAmount <= mainNodeCap, "exceeds main node capacity");
        mainNode.rewardAmount -= amount;
        mainNode.stakeAmount += amount;
        mainNode.totalStakeAmount += amount;

        currentTotalReward -= amount;
        totalRewardClaimed += amount;
        currentTotalStaked += amount;
        totalStaked += amount;

        emit ReStaked(msg.sender, info.lightNodeId, mainNodeId, amount, block.timestamp);
    }

    function claimReward(uint256 amount) public nonReentrant {
        require(block.timestamp >= initTime, "staking not started");
        require(amount > 0, "invalid amount");
        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake reward");

        uint256 claimableAmount = getDynamicReward(msg.sender) - dynamicRewardClaimed[msg.sender];
        require(amount <= claimableAmount, "Insufficient rewards");
        dynamicRewardClaimed[msg.sender] += amount;
        info.rewardAmount -= amount;
        info.updateTime = block.timestamp;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        lightNode.rewardAmount -= amount;

        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        mainNode.rewardAmount -= amount;
        
        currentTotalReward -= amount;
        totalRewardClaimed += amount;

        Address.sendValue(payable(msg.sender), amount);

        emit RewardClaimed(msg.sender, info.lightNodeId, lightNode.mainNodeId, amount, block.timestamp);
    }

    function unstake(uint256 amount) public nonReentrant{
        require(block.timestamp >= initTime, "staking not started");
        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake record");
        require(amount > 0 && info.stakeAmount >= amount, "no enough tokens to withdraw");

        info.updateTime = block.timestamp;
        info.stakeAmount -= amount;
        if(info.stakeAmount < stopLimit * 1e18)
            info.unstakeCount += 1;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        lightNode.stakeAmount -= amount;
        if(ownerLightNodeId[msg.sender] == info.lightNodeId && info.unstakeCount >= 3)
            lightNode.isStopped = true;

        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        mainNode.stakeAmount -= amount;

        currentTotalStaked -= amount;
        totalUnstaked += amount;
        unstakeInfo[msg.sender].push(UnstakeInfo(block.timestamp, amount, false, true));

        emit Unstaked(msg.sender, info.lightNodeId, lightNode.mainNodeId, amount, info.stakeAmount, block.timestamp);
    }

    function withdrawById(uint256 id) public nonReentrant{
        require(block.timestamp >= initTime, "staking not started");
        require(id < unstakeInfo[msg.sender].length, "invalid unstake id");
        UnstakeInfo storage info = unstakeInfo[msg.sender][id];
        require(info.isUsed, "no unstake record");
        require((block.timestamp - info.timestamp) >= 21 * 86400, "not released within 21 days"); 
        require(!info.isClaimed, "record has been claimed");
        Address.sendValue(payable(msg.sender), info.amount);
        info.isClaimed = true;
        uint256 leftAmount = getDynamicPrincipal(msg.sender);
        emit Withdraw(msg.sender, info.amount, leftAmount);
    }
}
