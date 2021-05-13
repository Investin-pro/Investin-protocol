pragma solidity 0.6.12;

import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

interface iIVN {
    function burn(uint256 amount) external;
}


contract IVNFarm is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.

    }

    // Info of each pool.
    struct PoolInfo {

        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. IVNs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that IVNs distribution occurs.
        uint256 accIVNPerShare; // Accumulated IVNs per share, times 1e12. See below.
    }

    // The REWARD TOKEN
    IERC20 public rewardToken;


    // IVN tokens rewarded per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.

    mapping (address => UserInfo) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when IVN mining starts.
    uint256 public startBlock;
    // The block number when IVN mining ends.
    uint256 public bonusEndBlock;
    // Check whether farm is funded or not?
    bool public initialized;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IERC20 _rewardToken,
        uint256 _rewardPerBlock
    ) public {
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        totalAllocPoint = 1000;

    }
    
    function initialize(IERC20 _lp, uint256 _amount) public onlyOwner{
        require(initialized==false, "Already Initialized");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        startBlock = block.number;
        bonusEndBlock = startBlock.add(_amount.div(rewardPerBlock));
        initialized = true;
        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _lp,
            allocPoint: 1000,
            lastRewardBlock: block.number,
            accIVNPerShare: 0
        }));
    }


    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }
    

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accIVNPerShare = pool.accIVNPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 IVNReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accIVNPerShare = accIVNPerShare.add(IVNReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accIVNPerShare).div(1e12).sub(user.rewardDebt);

    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 IVNReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accIVNPerShare = pool.accIVNPerShare.add(IVNReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Stake tokens to SmartChef
    function deposit(uint256 _amount) public {
        require(initialized==true, "deposit: Farm not initialzied yet");
        
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        

        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accIVNPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accIVNPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }


    // Withdraw tokens from STAKING.
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accIVNPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIVNPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }


    // Burn leftover reward tokens once farming ends
    function burnRemainingTokens() external onlyOwner{ 
        require(block.number >= bonusEndBlock.add(648000), "Can't burn yet");
        iIVN(address(rewardToken)).burn(rewardToken.balanceOf(address(this)));
    }
}
