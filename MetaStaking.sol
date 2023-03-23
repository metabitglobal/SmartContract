// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// main node -> light node -> user
contract MetaStaking is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct MainNodeInfo {
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 totalLightNodes;
        uint256 rate;            // rate for APR base is 10000
        uint256 commissionRate;  // commission rate of main node 
        bool isStopped;
        bool isUsed;
    }

    struct LightNodeInfo {
        uint256 mainNodeId;
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 totalUsers;
        uint256 registerTime;
        uint256 commissionRate;
        address ownerAddress;
        bool isStopped;
        bool isUsed;
    }

    struct StakeInfo {
        uint256 lightNodeId;
        uint256 updateTime;
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 unstakeCount;
        address referee; 
        bool isUsed;
    }

    event NewUser(address user, uint256 lightId, uint256 mainId, address referee, uint256 timestamp);
    event Staked( address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 rate, uint256 timestamp);
    event Unstaked(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 leftAmount, uint256 timestamp);
    event RewardClaimed(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 amount, uint256 timestamp);
    event NewStakeRate(uint256 nodeId, uint256 oldRate, uint256 newRate);
    event NewMainNodeCommission(uint256 nodeId, uint256 oldRate, uint256 rate);
    event NewLightNodeCommission(uint256 nodeId, uint256 oldRate, uint256 rate);
    event NewMainNode(uint256 id, uint256 timestamp);
    event NewLightNode(uint256 id, uint256 mainId, address owner, uint256 timestamp);
    event ReferRewardSet(uint256 batchNo);
    event ReStaked(address indexed account, uint256 indexed lightNodeId, uint256 indexed mainNodeId, uint256 reward, uint256 timestamp);

    mapping (uint256 => MainNodeInfo) public mainNodeInfo;  // node id -> info
    mapping (uint256 => LightNodeInfo) public lightNodeInfo; // node id -> info
    mapping (address => uint256) public ownerLightNodeId; // owner address -> node id
    mapping (address => StakeInfo) public stakeInfo; // address -> stake info
    mapping (address => uint256) public referRewards; // address -> refer award 
    mapping (address => bool) public lightNodeBlacklist; // address -> refer award 
    mapping (uint256 => mapping(address => uint256)) public dynamicReward; // date -> (address -> award) 
    mapping (address => uint256) public firstDynamicRecord; // address -> date 
    mapping (address => uint256) public dynamicRewardClaimed; // address -> amount claimed

    uint256 constant BASE = 10000;  // APR ratio base
    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;  // seconds per day
    uint256 constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;  // seconds per year 
    uint256 constant DEFAULT_RATE = 10000;  // default APR rate 
    uint256 public currentTotalStaked;  // current total staked in the contract
    uint256 public currentTotalReward;  // current total reward available for claiming
    uint256 public totalStaked;     // total staked amount (including unstaked)
    uint256 public totalReward;     // total reward generated (inlcuding claimed)
    uint256 public totalUnstaked;   // total unstaked 
    uint256 public totalRewardClaimed; // total reward claimed
    uint256 public stopLimit; // stop limit of light node 

    uint256 public mainNodeCap;     // staking cap for every main node  
    uint256 public currentMainNodeIndex; // start from 1
    uint256 public currentLightNodeIndex; // start from 1
    uint256 public initTime; // init time for staking 

    /// @notice initialize only run once
    function initialize () public initializer {
      __Ownable_init();
      __UUPSUpgradeable_init();
      currentMainNodeIndex = 1;
      currentLightNodeIndex = 1;
      stopLimit = 1000;
      mainNodeCap = 4_000_000 * 1 ether;
      initTime = 1680278400; // since April 1st
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    receive() external payable {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _setInitTime(uint256 timestamp) external onlyOwner {
        initTime = timestamp;
    }

    function _setStopLimit(uint256 limit) external onlyOwner {
        stopLimit = limit;
    }

    function _setMainNodeStakeRate(uint256 id, uint256 ratio) external onlyOwner {
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node does not exists.");
        uint256 oldRate = node.rate;
        node.rate = ratio;
        emit NewStakeRate(id, oldRate, node.rate);
    }

    function _setMainNodeCommissionRate(uint256 id, uint256 rate) external onlyOwner {
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node does not exists.");
        uint256 oldRate = node.commissionRate;
        node.commissionRate = rate;
        emit NewMainNodeCommission(id, oldRate, rate);
    }

    function _setLightNodeCommissionRate(uint256 id, uint256 rate) external onlyOwner {
        LightNodeInfo storage node = lightNodeInfo[id];
        require(node.isUsed, "light node does not exists.");
        uint256 oldRate = node.commissionRate;
        node.commissionRate = rate;
        emit NewLightNodeCommission(id, oldRate, rate);
    }

    function _initMainNode(uint256 num) external onlyOwner returns (uint256[] memory) {
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

    function _setReferReward(uint256 batchNo, address[] calldata accounts, uint256[] calldata values) external onlyOwner {
        require(batchNo != 0, "batchNo cannot be empty");
        require(accounts.length == values.length, "length not match");
        
        uint256 key = block.timestamp / SECONDS_PER_DAY;
        for(uint i=0; i<accounts.length; i++)
        {
            if(firstDynamicRecord[accounts[i]] == 0)
                firstDynamicRecord[accounts[i]] = key;
            dynamicReward[key][accounts[i]] = values[i];
            updateNodesInfo(accounts[i], values[i]);
        }
        emit ReferRewardSet(batchNo);
    }

    // get claimable dynamic reward
    function getDynamicReward(address account) public view returns(uint256) {
        uint256 day = block.timestamp / SECONDS_PER_DAY;
        uint256 firstDate = firstDynamicRecord[account];
        if(firstDate == 0)
            return 0;

        uint256 totalDynamicReward = 0;
        for(uint i = 0; i < 365; i++)
        {
            uint256 key = day - i;
            if(key < firstDate)
                break;
            totalDynamicReward += dynamicReward[key][account]*(i+1)/365;
        }
        return totalDynamicReward;
    }

    function registerLightNode(uint256 id, address account, address referee) external onlyOwner returns(uint256) {
        require(!lightNodeBlacklist[account], "account has a lightnode already");
        MainNodeInfo storage node = mainNodeInfo[id];
        require(node.isUsed, "main node not exist");

        if(referee != address(0))
        {
            StakeInfo memory refereeUser = stakeInfo[referee];
            require(refereeUser.isUsed, "referee not exist");
        }
        node.totalLightNodes += 1;
        LightNodeInfo memory lightNode = LightNodeInfo(id, 0, 0, 0, 0, 0, block.timestamp, 500, account, false, true);
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
        emit NewUser(account, lightNodeId, id, referee, block.timestamp);

        return lightNodeId;
    }

    function reward(address account) public view returns (uint256) {
        StakeInfo memory info = stakeInfo[account];
        if(info.isUsed)
        {
            return info.rewardAmount - dynamicRewardClaimed[account];
        }else
            return 0;
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
        mainNode.stakeAmount += msg.value;
        mainNode.totalStakeAmount += msg.value;
        currentTotalStaked += msg.value;
        totalStaked += msg.value;

        emit Staked(msg.sender, info.lightNodeId, mainNodeId, msg.value, rate, block.timestamp);
    }

    // restake
    function restake() public payable {

        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake record");
        uint256 dReward = getDynamicReward(msg.sender);
        uint256 amount = dReward - dynamicRewardClaimed[msg.sender];
        dynamicRewardClaimed[msg.sender] = dReward;

        info.stakeAmount += amount;
        info.totalStakeAmount += amount;
        info.rewardAmount = 0;
        info.totalRewardAmount += amount;
        info.updateTime = block.timestamp;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        require(lightNode.isUsed && !lightNode.isStopped, "light node stopped");
        lightNode.stakeAmount += amount;
        lightNode.rewardAmount += amount;
        lightNode.totalStakeAmount += amount;
        lightNode.totalRewardAmount += amount;
        uint256 mainNodeId = lightNode.mainNodeId;
        
        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        require(mainNode.isUsed && !mainNode.isStopped, "main node stopped");
        mainNode.stakeAmount += amount;
        mainNode.rewardAmount += amount;
        mainNode.totalStakeAmount += amount;
        mainNode.totalRewardAmount += amount;

        currentTotalReward += amount;
        totalReward += amount;
        currentTotalStaked += amount;
        totalStaked += amount;

        emit ReStaked(msg.sender, info.lightNodeId, mainNodeId, amount, block.timestamp);
    }

    function claimReward(uint256 amount) public nonReentrant {
        require(amount > 0, "invalid amount");
        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake reward");

        uint256 claimableAmount = getDynamicReward(msg.sender) - dynamicRewardClaimed[msg.sender];
        require(amount <= claimableAmount, "Insufficient rewards");
        dynamicRewardClaimed[msg.sender] += amount;
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
        StakeInfo storage info = stakeInfo[msg.sender];
        require(info.isUsed, "no stake record");
        require(amount > 0 && info.stakeAmount >= amount, "no enough tokens to withdraw");

        info.updateTime = block.timestamp;
        info.stakeAmount -= amount;
        if(info.stakeAmount < stopLimit * 1e18)
            info.unstakeCount += 1;

        LightNodeInfo storage lightNode = lightNodeInfo[info.lightNodeId];
        lightNode.stakeAmount -= amount;
        if(info.unstakeCount >= 3)
            lightNode.isStopped = true;

        MainNodeInfo storage mainNode = mainNodeInfo[lightNode.mainNodeId];
        mainNode.stakeAmount -= amount;

        currentTotalStaked -= amount;
        totalUnstaked += amount;
        Address.sendValue(payable(msg.sender), amount);

        emit Unstaked(msg.sender, info.lightNodeId, lightNode.mainNodeId, amount, info.stakeAmount, block.timestamp);
    }
}
