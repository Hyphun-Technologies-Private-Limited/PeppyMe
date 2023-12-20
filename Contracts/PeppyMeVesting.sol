// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract PeppyMeTokenVesting{
    IERC20 public token;
    struct VestingInfo{
        uint vestingId;
        uint startTime;
        uint duration;
        uint cliff;
        uint slicePeriod;
        uint tokensAmount;
        uint releasedTokens;
    }
    
    struct BeneficiaryInfo{
        uint id;
        mapping(IERC20 => VestingInfo[]) vestingSchedules;
    }
    mapping (address => BeneficiaryInfo) public beneficiaries;

    // Events
    event VestTokensEvent(address beneficiary, string  message);
    event ReleaseTokensEvent(address beneficiary, uint amountReleased, string message);

    // Modifiers
    modifier cliffPeriodOver(address _beneficiary, uint _id){
        require(block.timestamp >= beneficiaries[_beneficiary].vestingSchedules[token][_id].cliff, "Wait Till Cliff period");
         _;
    }
    modifier isBeneficiary(address _beneficiary){
        require( msg.sender==_beneficiary,"Only Beneficiary can Lock and Release Tokens");
         _;
    }

    constructor(IERC20 _token)
        {
        token = _token;
    }

    // Locking Tokens of beneficiary
    function VestTokens(address _beneficiaryAddress,uint _tokensAmount,uint _cliff,uint _duration,uint _slicePeriod) isBeneficiary(_beneficiaryAddress) public {
        require(_slicePeriod<=_duration &&_cliff<=_duration,"Slice period & cliff should be < Duration");
        require(_tokensAmount>0,"Tokens to vest should be > 0");
        uint _cliffTime = _cliff * 1 days;
        VestingInfo[] storage vestingsOfToken = beneficiaries[_beneficiaryAddress].vestingSchedules[token];
        VestingInfo memory currentVesting= VestingInfo({
            vestingId: vestingsOfToken.length,
            startTime: block.timestamp,
            duration: _duration * 1 days,
            cliff:block.timestamp+ _cliffTime,
            slicePeriod: _slicePeriod,
            tokensAmount: _tokensAmount,
            releasedTokens: 0
        });
        vestingsOfToken.push(currentVesting);
        token.transferFrom(msg.sender, address(this), _tokensAmount);
        emit VestTokensEvent(_beneficiaryAddress, "Tokens are vested successfully");
    }
      // Get Details of particular vesting of beneficiary
      function getVestingDetails(address _beneficiaryAddress, uint _id )public view returns(VestingInfo memory){
          return beneficiaries[_beneficiaryAddress].vestingSchedules[token][_id];
      }

    // Calculate no. of eligible tokens to release
    function releasableTokens(address _beneficiary,uint _id) internal view  returns(uint) {
        VestingInfo memory vestingInstance =  beneficiaries[_beneficiary].vestingSchedules[token][_id];
        uint timeSinceStart = block.timestamp - vestingInstance.startTime;
        uint noOfPeriodsSinceStart = timeSinceStart/vestingInstance.slicePeriod;
        uint totalPeriods =vestingInstance.duration /vestingInstance.slicePeriod;
        uint releasedTokens=vestingInstance.releasedTokens;
        uint totalTokenAmount=vestingInstance.tokensAmount;
        if (noOfPeriodsSinceStart >= totalPeriods ) {
            return totalTokenAmount-releasedTokens;
        } 
        else {
            uint tokensReleasedInOnePeriod =totalTokenAmount/ totalPeriods;
            uint tokensToBeReleased = tokensReleasedInOnePeriod * noOfPeriodsSinceStart;
            tokensToBeReleased=tokensToBeReleased-releasedTokens;
            return tokensToBeReleased;
        }
    }
    
    // Release  tokens to beneficiary
    function claimTokens(address _beneficiary,uint _id ,uint _claimAmount) isBeneficiary(_beneficiary) cliffPeriodOver(_beneficiary,_id) public {
        uint tokensToBeReleased = releasableTokens(_beneficiary, _id);
        require(tokensToBeReleased > 0, "No tokens for release");
        require(_claimAmount<=tokensToBeReleased,"Claim Amount > Releasable tokens");
        VestingInfo  storage vestingInstance =  beneficiaries[_beneficiary].vestingSchedules[token][_id];
        vestingInstance.releasedTokens += _claimAmount;
        token.transfer(_beneficiary, _claimAmount); 
        emit ReleaseTokensEvent(_beneficiary, _claimAmount,"Tokens released to beneficiary");
    }

    }