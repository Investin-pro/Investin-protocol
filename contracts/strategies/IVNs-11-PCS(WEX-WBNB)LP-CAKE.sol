// SPDX-License-Identifier: MIT
//["0xEdF7C00695Df3D227D89d26901b3F815BFf44e6a"]
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol";
//import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

interface iMasterChef{
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingCake(uint256 _pid, address _user) external view returns (uint256);
    function emergencyWithdraw(uint256 _pid) external;
}

interface iIVNyToken {
    function investinVault() external view returns (address);
}

interface iStrategy{
    function getStrategyTokenPrice() external view returns (uint);
    function exit(uint256 amount) external;
    function enter(uint256 amount, bool isFund) external;
    function emergencyExit(uint256 amount) external;
    // function baseToken() view external returns(address);
}

interface iRouter {
    struct FundInfo{
        bool isActive;
        uint128 amountInRouter;
    }
    function getFundMapping (address _fund) external view returns(FundInfo memory);
}

interface iExchangeRouter{
    function getAmountsOut(uint amountIn, address[] memory path) view external returns (uint[] memory amounts);
    function factory() external view returns (address);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface iExchangePair is IERC20{
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
// Investintoken with Governance.
contract InvestinStrategyToken is ERC20("PCS(WEX-WBNB)LP-CAKE", "IVNs-11"), Ownable, ReentrancyGuard, iStrategy {//3213k 3172k 
    address constant stableCoin = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public constant baseToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    iExchangeRouter constant exchangeRouter = iExchangeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    iExchangePair constant lPToken = iExchangePair(0x547A355E70cd1F8CAF531B950905aF751dBEF5E6);
    address constant token0 = 0xa9c41A46a6B3531d28d5c32F6633dd2fF05dFB90;
    address constant token1 = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    iMasterChef constant rewardPool = iMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    uint256 constant pid = 418;
    address constant rewardToken = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    
    uint constant MAX_UINT_VALUE = type(uint).max;
    
    uint256 public principalStaked;
    uint256 public reinvestIncentive = 1e6; //1%
    uint256 public entryFee = 1e5; //0.1%
    
    address[] fundFactories;
    
    iIVNyToken constant IVNy = iIVNyToken(0x238265541dfd73ef6297A3dBF7C62fBDE7A5dfFB);
    
    // address[] public path_BaseToToken0;
    // address[] public path_BaseToToken1;
    // address[] public path_RewardToToken0;
    // address[] public path_RewardToToken1;
    // address[] public path_Token0ToBase;
    // address[] public path_Token1ToBase;
    
    bool public isActive = true;
    bool status = true;
    
  constructor(address[] memory _fundFactories) public {
        fundFactories = _fundFactories;//0xE8Ee74337d10CF49578F1B84113383ae3CB4570b
        IERC20(baseToken).approve(address(exchangeRouter), MAX_UINT_VALUE);
        IERC20(token0).approve(address(exchangeRouter), MAX_UINT_VALUE);
        //IERC20(token1).approve(exchangeRouter, MAX_UINT_VALUE); token1 == basetoken == WBNB
        lPToken.approve(address(rewardPool), MAX_UINT_VALUE);
        IERC20(rewardToken).approve(address(exchangeRouter), MAX_UINT_VALUE);
        lPToken.approve(address(exchangeRouter), MAX_UINT_VALUE);
        
    }
    
    function addFactory(address[] calldata _fundFactories) external onlyOwner{
        for(uint i = 0; i<_fundFactories.length; i++){
            fundFactories.push(_fundFactories[i]);
        }
    }
    
    function updateEntryFee(uint val) external onlyOwner{
        require(val<=1e6, "NV");//1% max
        entryFee = val;
    }
    
    function updateReinvestIncentive(uint amt) external onlyOwner{
        require(amt<=1e7, "NV");//10% max
        reinvestIncentive = amt;
    }
    
    function updateActivityStatus(bool _value) external onlyOwner{
        isActive = _value;
    }

    
    function viewPendingRewards() external view returns(uint rewardAmt){
        rewardAmt = rewardPool.pendingCake(pid, address(this));
    }
    
    
    function enter(uint256 amount, bool isFund) external override nonReentrant{
        require(isActive && status, "SiA");
        IERC20(baseToken).transferFrom(msg.sender, address(this), amount);
        
        if(isFund==true){
            isFund = false;
            address[] memory _fundFactories = fundFactories;
            for(uint i=0;i<_fundFactories.length;i++){
                if(iRouter(_fundFactories[i]).getFundMapping(msg.sender).isActive){
                    isFund = true;
                    break;
                }
            }
        }
        if(isFund==false){
            uint _entryFee = (amount.mul(entryFee)) / 1e8;
            IERC20(baseToken).transfer(IVNy.investinVault(), _entryFee);
            amount -= _entryFee;
        }
        
        uint token0Amount;// = amount/2;
        uint token1Amount;// = amount/2;
        //if(_baseToken!=_token0){
            address[] memory path_BaseToToken0 = new address[](2); // path_BaseToToken0 here token1 == basetoken
            path_BaseToToken0[0] = baseToken;
            path_BaseToToken0[1] = token0;
            ( , uint resT1, ) = lPToken.getReserves();
            uint swapAmount = calcOptimalSwapAmt(resT1, amount);
            token1Amount = amount.sub(swapAmount);
            token0Amount = exchangeRouter.swapExactTokensForTokens(swapAmount, 0, path_BaseToToken0, address(this), block.timestamp)[1];
            
        //}
        // if(_baseToken!=_token1){
            // address[] memory path_BaseToToken1 = new address[](2);
            // path_BaseToToken1[0] = baseToken;
            // path_BaseToToken1[1] = token1;
            //token1Amount = exchangeRouter.swapExactTokensForTokens(amount/2, 1, path1, address(this), block.timestamp)[1];
        // }
        
        (, , uint liquidity) = exchangeRouter.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, address(this), block.timestamp);
        require(liquidity>0, "ALF");
        
        uint _totalSupply = totalSupply();
        uint multiplier = _totalSupply != 0 ? (_totalSupply.mul( 1e18 )).div(principalStaked) : 0;
        
        rewardPool.deposit(pid, liquidity);
        principalStaked = principalStaked.add(liquidity);
        
        if( _totalSupply > 0 ){
            liquidity = (liquidity.mul(multiplier)).div(1e18);
        }
        
        _mint(msg.sender, liquidity);
        
    }
    
    
    function exitHelper(uint256 mv) internal{
        (uint token0Amount, uint token1Amount) = exchangeRouter.removeLiquidity(token0, token1, mv, 0, 0, address(this), block.timestamp);
        // if(_baseToken != _token0){
            address[] memory path_Token0toBase = new address[](2);
            path_Token0toBase[0] = token0;
            path_Token0toBase[1] = baseToken;
            token0Amount = exchangeRouter.swapExactTokensForTokens(token0Amount, 1, path_Token0toBase, address(this), block.timestamp)[1];
        // }
        // if(_baseToken != _token1){
            // address[] memory path1 = new address[](2);
            // path1[0] = _token1;
            // path1[1] = _baseToken;
            // token1Amount = exchangeRouter.swapExactTokensForTokens(token1Amount, 1, path1, address(this), block.timestamp)[1];
        // }
        IERC20(baseToken).transfer(msg.sender, token1Amount.add(token0Amount));
    }
    
    function calcOptimalSwapAmt(uint res, uint amt) internal pure returns (uint swapAmount){
        swapAmount = (sqrt(res.mul((res.mul(399000625)).add(amt.mul(398680800)))).sub(res.mul(19975))).div(19934);
    }
     
    function exit(uint256 amount) external override nonReentrant{
        uint mv = (amount.mul((principalStaked.mul(1e18)).div(totalSupply()))).div(1e18);
        _burn(msg.sender, amount);
        if( status ) {
            rewardPool.withdraw(pid, mv);   
        }
        principalStaked = principalStaked.sub(mv);
        exitHelper(mv);
        
    }
    
    function emergencyExit(uint256 amount) public override nonReentrant{
        uint mv = (amount.mul((principalStaked.mul(1e18)).div(totalSupply()))).div(1e18);
        _burn(msg.sender, amount);
        principalStaked = principalStaked.sub(mv);
        exitHelper(mv);
    }
    
    function invokeEmergencyWithdraw() external onlyOwner {
        rewardPool.emergencyWithdraw(pid);
        status = false;
    }
    
    
    
    function reinvest() public nonReentrant{
        require(status==true, "SiA");
        rewardPool.withdraw(pid, 0);
        uint256 reward = IERC20(rewardToken).balanceOf(address(this));
        require(reward > 0, "NRA");
        uint256 bounty = (reward.mul(reinvestIncentive)).div(1e8);
        IERC20(rewardToken).transfer(msg.sender, bounty);
        reward = reward.sub(bounty);
        
        //Swaping @ll reward CAKE to WBNB and then swap an optimal amount of WBNB to WEX to add liquidity 
        address[] memory path_RewardToToken = new address[](2);
        path_RewardToToken[0] = rewardToken;
        path_RewardToToken[1] = token1;
        uint token1Amount = exchangeRouter.swapExactTokensForTokens(reward, 0, path_RewardToToken, address(this), block.timestamp)[1];
        
        (path_RewardToToken[0], path_RewardToToken[1]) = (token1, token0);
        ( , uint resT1, ) = lPToken.getReserves();
        uint swapAmount = calcOptimalSwapAmt(resT1, token1Amount);
        token1Amount = token1Amount.sub(swapAmount);
        uint token0Amount = exchangeRouter.swapExactTokensForTokens(swapAmount, 0, path_RewardToToken, address(this), block.timestamp)[1];
        
        // address[] memory path = new address[](2);
        // path[0] = _token1;
        // path[1] = _token0;
        // token0Amount = exchangeRouter.swapExactTokensForTokens(token1Amount/2, 1, path, address(this), block.timestamp)[1];
        
        // if(_rewardToken!=_token0){
        //     address[] memory path = new address[](2);
        //     path[0] = _rewardToken;
        //     path[1] = _token0;
        //     token0Amount = exchangeRouter.swapExactTokensForTokens(reward/2, 1, path, address(this), block.timestamp)[1];
        // }
        // if(_rewardToken!=_token1){
        //     address[] memory path1 = new address[](2);
        //     path1[0] = _rewardToken;
        //     path1[1] = _token1;
        //     token1Amount = exchangeRouter.swapExactTokensForTokens(reward/2, 1, path1, address(this), block.timestamp)[1];
        // }
        
        
        (, , uint liquidity) = exchangeRouter.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, address(this), block.timestamp);
        require(liquidity>0, "ALF");
        rewardPool.deposit(pid, liquidity);
        principalStaked = principalStaked.add(liquidity);
    }
    
    function collectDust(address _token) external onlyOwner{
        require(totalSupply() == 0, "NY");
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }
    
    function kill() external onlyOwner{
        require(totalSupply() == 0, "NY");
        selfdestruct(msg.sender);
    }
    
    
    function getStrategyTokenPrice() public view override returns (uint) {
        uint LPtotalSupply = lPToken.totalSupply();
        uint sqrtR;
        {
            (uint r0, uint r1, ) = lPToken.getReserves();
            sqrtR = sqrt(r0.mul(r1));
        }
        address[] memory path_TokentoStableCoin = new address[](2);
        path_TokentoStableCoin[0] = token0;
        path_TokentoStableCoin[1] = token1;
        uint p0_1 = exchangeRouter.getAmountsOut(1e18, path_TokentoStableCoin)[1];
        (path_TokentoStableCoin[0], path_TokentoStableCoin[1]) = (token1, stableCoin);
        uint p1 = exchangeRouter.getAmountsOut(1e18, path_TokentoStableCoin)[1]; 
        //Calculate price of token0 interms of token1 and then normalize with actual price of token1 (interms of stabelcoin) -coz no WEX/BNB pool exists
        uint sqrtP = (sqrt(p0_1.mul(1e18))).mul(p1).div(1e18);
        // else{
        //     sqrtP = (sqrt(p0.mul(p1)).mul(getTokenPrice(_baseToken, stableCoin))).div(1e18);
        // }
        
        uint _totalSupply = totalSupply();
        if(_totalSupply!=0)
            return (((sqrtR.mul(sqrtP).mul(2)).div(LPtotalSupply)).mul((principalStaked.mul(1e18)).div(_totalSupply))).div(1e18);
        else
            return ((sqrtR.mul(sqrtP).mul(2)).div(LPtotalSupply));
    }
    
    function sqrt(uint x) public pure returns (uint) {
        uint z = (x + 1) / 2;
        uint y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    
}
