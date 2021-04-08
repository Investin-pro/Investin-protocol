// SPDX-License-Identifier: MIT
//add a tvl require for managers to stake and earn ivn
pragma solidity  ^0.6.0;

import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/Investin-pro/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

//You come in with some IVN, and leave with more! The longer you stay, the more IVN you get.
//
// This contract handles swapping to and from xIVN, IVNSwap's staking token.
contract earn_IVN is ERC20("earn_IVN", "xIVN"){
    using SafeMath for uint256;
    IERC20 public IVN;

    // Define the IVN token contract
    constructor(IERC20 _IVN) public {
        IVN = _IVN;
    }

    // Enter the bar. Pay some IVNs. Earn some shares.
    // Locks IVN and mints xIVN
    function enter(uint256 _amount) public {
        // Gets the amount of IVN locked in the contract
        uint256 totalIVN = IVN.balanceOf(address(this));
        // Gets the amount of xIVN in existence
        uint256 totalShares = totalSupply();
        // If no xIVN exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalIVN == 0) {
            _mint(msg.sender, _amount);
        } 
        // Calculate and mint the amount of xIVN the IVN is worth. The ratio will change overtime, as xIVN is burned/minted and IVN deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalIVN);
            _mint(msg.sender, what);
        }
        // Lock the IVN in the contract
        IVN.safeTransferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your IVNs.
    // Unlocks the staked + gained IVN and burns xIVN
    function leave(uint256 _share) public {
        // Gets the amount of xIVN in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of IVN the xIVN is worth
        uint256 what = _share.mul(IVN.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        IVN.transfer(msg.sender, what);
    }
