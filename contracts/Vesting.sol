pragma solidity  ^0.6.0;

import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";
import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/aak-capital/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

/**
 * @title TokenVesting
 * @dev A token holder contract that can release its token balance gradually like a
 * typical vesting scheme, with a vesting period. Optionally revocable by the
 * owner.
 */
contract TokenVesting is Ownable {
    // The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and is
    // therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree). Therefore,
    // it is recommended to avoid using short time durations (less than a minute). Typical vesting schemes, with a
    // a duration of four years, are safe to use.
    // solhint-disable not-rely-on-time

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);
    event TokenVestingRevoked(address token);

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 private _start;
    uint256 private _duration;
    uint256 private _cycle = 1;
    uint256 private _totalCycles;

    bool private _revocable;

    mapping (address => uint256) private _released;
    mapping (address => bool) private _revoked;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * beneficiary, gradually in a linear fashion until start + duration. By then all
     * of the balance will have vested.
     * @param beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param duration duration in seconds of the period in which the tokens will vest
     * @param totalCycles total number of cycles covering the duration in which the tokens will vest
     * @param revocable whether the vesting is revocable or not
     */
    constructor (address beneficiary, uint256 duration, uint256 totalCycles, bool revocable) public {
        require(beneficiary != address(0), "TokenVesting: beneficiary is the zero address");
        require(duration > 0, "TokenVesting: duration is 0");
        _beneficiary = beneficiary;
        _revocable = revocable;
        _duration = duration;
        _totalCycles = totalCycles;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the start time of the token vesting.
     */
    function start() public view returns (uint256) {
        return _start;
    }
    
    /**
     * @return the current cycle of the token vesting.
     */
    function cycle() public view returns (uint256) {
        return _cycle;
    }
    
    /**
     * @return the total number of cycles in the token vesting.
     */
    function totalCycles() public view returns (uint256) {
        return _totalCycles;
    }
    
    

    /**
     * @return the duration of the token vesting.
     */
    function duration() public view returns (uint256) {
        return _duration;
    }

    /**
     * @return true if the vesting is revocable.
     */
    function revocable() public view returns (bool) {
        return _revocable;
    }
    
    function timenow() public view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address token) public view returns (uint256) {
        return _released[token];
    }

    /**
     * @return true if the token is revoked.
     */
    function revoked(address token) public view returns (bool) {
        return _revoked[token];
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param token ERC20 token which is being vested
     */
    function release(IERC20 token) public {
        require(timenow()>=_start.add(((_duration).mul(_cycle)).div(_totalCycles)), "TokenVesting: Cycle not complete yet");
        uint256 unreleased = _releasableAmount(token);

        require(unreleased > 0, "TokenVesting: no tokens are due");

        _released[address(token)] = _released[address(token)].add(unreleased);

        token.safeTransfer(_beneficiary, unreleased);
        
        _cycle++;

        emit TokensReleased(address(token), unreleased);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param token ERC20 token which is being vested
     */
    function revoke(IERC20 token) public onlyOwner {
        require(_revocable, "TokenVesting: cannot revoke");
        require(!_revoked[address(token)], "TokenVesting: token already revoked");

        uint256 balance = token.balanceOf(address(this));

        uint256 unreleased = _releasableAmount(token);
        uint256 refund = balance.sub(unreleased);

        _revoked[address(token)] = true;

        token.safeTransfer(owner(), refund);

        emit TokenVestingRevoked(address(token));
    }
    
    /**
     * @param start the time (as Unix time) at which point vesting starts
     */
    function setStart(uint256 start) public onlyOwner{
        require(_start==0, "TokenVesting: start already set ");
        require(start.add(_duration) > block.timestamp, "TokenVesting: final time is before current time");
        _start = start;
    }
    
    function nextRelease() public view returns(uint256){
        return _start.add(((_duration).mul(_cycle)).div(_totalCycles));
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param token ERC20 token which is being vested
     */
    function _releasableAmount(IERC20 token) public view returns (uint256) {
        return _vestedAmount(token).sub(_released[address(token)]);
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param token ERC20 token which is being vested
     */
    function _vestedAmount(IERC20 token) public view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 totalBalance = currentBalance.add(_released[address(token)]);

        if (block.timestamp >= _start.add(_duration) || _revoked[address(token)]) {
            return totalBalance;
        } else {
            return totalBalance.mul(_cycle).div(_totalCycles);
        }
    }
}
