// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";

/**
 * @title VestingContract
 * @notice Diamond Vesting Curve (DVC): 5% at TGE, 95% linear over 7 years
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev Beneficiaries and allocations set at deployment (immutable)
 * @dev Vesting starts automatically at deployment
 */
contract VestingContract {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidBeneficiary();
    error InvalidAmount();
    error NothingToClaim();
    error TransferFailed();
    error ArrayLengthMismatch();
    error InsufficientBalance();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TGE_PERCENT = 5;
    uint256 public constant VESTING_PERCENT = 95;
    uint256 public constant VESTING_DURATION = 7 * 365 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    IDMDToken public immutable dmdToken;

    /// @notice TGE timestamp (set at deployment)
    uint256 public immutable tgeTime;

    /// @notice Total allocation across all beneficiaries
    uint256 public immutable totalAllocation;

    struct Beneficiary {
        uint256 totalAllocation;    // Total DMD allocated
        uint256 claimed;            // Amount already claimed
    }

    mapping(address => Beneficiary) public beneficiaries;
    address[] public beneficiaryList;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BeneficiaryRegistered(address indexed beneficiary, uint256 allocation);
    event VestingStarted(uint256 tgeTime);
    event Claimed(address indexed beneficiary, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy vesting contract with beneficiaries and start immediately
     * @param _dmdToken Address of DMD token contract
     * @param _beneficiaries Array of beneficiary addresses
     * @param _allocations Array of allocation amounts (must match beneficiaries length)
     * @dev Vesting begins immediately at deployment - no owner needed
     * @dev Contract must be funded with DMD tokens before beneficiaries can claim
     */
    constructor(
        IDMDToken _dmdToken,
        address[] memory _beneficiaries,
        uint256[] memory _allocations
    ) {
        if (address(_dmdToken) == address(0)) revert InvalidBeneficiary();
        if (_beneficiaries.length == 0) revert InvalidBeneficiary();
        if (_beneficiaries.length != _allocations.length) revert ArrayLengthMismatch();

        dmdToken = _dmdToken;
        tgeTime = block.timestamp;

        uint256 total = 0;

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            uint256 allocation = _allocations[i];

            if (beneficiary == address(0)) revert InvalidBeneficiary();
            if (allocation == 0) revert InvalidAmount();
            if (beneficiaries[beneficiary].totalAllocation != 0) revert InvalidBeneficiary(); // No duplicates

            beneficiaries[beneficiary] = Beneficiary({
                totalAllocation: allocation,
                claimed: 0
            });

            beneficiaryList.push(beneficiary);
            total += allocation;

            emit BeneficiaryRegistered(beneficiary, allocation);
        }

        totalAllocation = total;

        emit VestingStarted(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim vested DMD
     * @dev Beneficiary calls to receive their vested tokens
     */
    function claim() external {
        Beneficiary storage beneficiary = beneficiaries[msg.sender];
        if (beneficiary.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 vested = _vestedAmount(msg.sender);
        uint256 claimable = vested - beneficiary.claimed;

        if (claimable == 0) revert NothingToClaim();

        // Check contract has sufficient balance
        if (dmdToken.balanceOf(address(this)) < claimable) revert InsufficientBalance();

        beneficiary.claimed += claimable;

        bool success = dmdToken.transfer(msg.sender, claimable);
        if (!success) revert TransferFailed();

        emit Claimed(msg.sender, claimable);
    }

    /**
     * @notice Claim on behalf of beneficiary (anyone can trigger)
     * @param beneficiary Address to claim for
     * @dev Permissionless - allows third parties to trigger claims for beneficiaries
     */
    function claimFor(address beneficiary) external {
        Beneficiary storage ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 vested = _vestedAmount(beneficiary);
        uint256 claimable = vested - ben.claimed;

        if (claimable == 0) revert NothingToClaim();

        // Check contract has sufficient balance
        if (dmdToken.balanceOf(address(this)) < claimable) revert InsufficientBalance();

        ben.claimed += claimable;

        bool success = dmdToken.transfer(beneficiary, claimable);
        if (!success) revert TransferFailed();

        emit Claimed(beneficiary, claimable);
    }

    /**
     * @notice Batch claim for multiple beneficiaries
     * @param _beneficiaries Array of beneficiary addresses
     * @dev Permissionless - anyone can trigger batch claims
     */
    function claimMultiple(address[] calldata _beneficiaries) external {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            Beneficiary storage ben = beneficiaries[beneficiary];

            if (ben.totalAllocation == 0) continue;

            uint256 vested = _vestedAmount(beneficiary);
            uint256 claimable = vested - ben.claimed;

            if (claimable == 0) continue;

            // Check contract has sufficient balance
            if (dmdToken.balanceOf(address(this)) < claimable) continue;

            ben.claimed += claimable;

            bool success = dmdToken.transfer(beneficiary, claimable);
            if (!success) continue;

            emit Claimed(beneficiary, claimable);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get claimable amount for beneficiary
     */
    function getClaimable(address beneficiary) external view returns (uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) return 0;

        uint256 vested = _vestedAmount(beneficiary);
        return vested > ben.claimed ? vested - ben.claimed : 0;
    }

    /**
     * @notice Get vested amount (total unlocked so far)
     */
    function getVested(address beneficiary) external view returns (uint256) {
        return _vestedAmount(beneficiary);
    }

    /**
     * @notice Get beneficiary details
     */
    function getBeneficiary(address beneficiary)
        external
        view
        returns (
            uint256 _totalAllocation,
            uint256 claimed,
            uint256 vested,
            uint256 claimable
        )
    {
        Beneficiary memory ben = beneficiaries[beneficiary];
        _totalAllocation = ben.totalAllocation;
        claimed = ben.claimed;
        vested = _vestedAmount(beneficiary);
        claimable = vested > claimed ? vested - claimed : 0;
    }

    /**
     * @notice Get all beneficiaries
     */
    function getAllBeneficiaries() external view returns (address[] memory) {
        return beneficiaryList;
    }

    /**
     * @notice Get total number of beneficiaries
     */
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaryList.length;
    }

    /**
     * @notice Get contract's current DMD balance
     */
    function getContractBalance() external view returns (uint256) {
        return dmdToken.balanceOf(address(this));
    }

    /**
     * @notice Check if contract has sufficient balance for all remaining claims
     */
    function isSufficientlyFunded() external view returns (bool) {
        uint256 remaining = 0;
        for (uint256 i = 0; i < beneficiaryList.length; i++) {
            Beneficiary memory ben = beneficiaries[beneficiaryList[i]];
            remaining += ben.totalAllocation - ben.claimed;
        }
        return dmdToken.balanceOf(address(this)) >= remaining;
    }

    /**
     * @notice Get time elapsed since TGE
     */
    function getTimeElapsed() external view returns (uint256) {
        return block.timestamp - tgeTime;
    }

    /**
     * @notice Get vesting progress as percentage (0-100)
     */
    function getVestingProgress() external view returns (uint256) {
        uint256 elapsed = block.timestamp - tgeTime;
        if (elapsed >= VESTING_DURATION) return 100;
        return (elapsed * 100) / VESTING_DURATION;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    function _vestedAmount(address beneficiary) internal view returns (uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) return 0;

        // Calculate TGE amount (5%)
        uint256 tgeAmount = (ben.totalAllocation * TGE_PERCENT) / 100;

        // If before TGE (shouldn't happen since TGE is at deployment)
        if (block.timestamp < tgeTime) {
            return 0;
        }

        // TGE immediate unlock
        if (block.timestamp == tgeTime) {
            return tgeAmount;
        }

        // Calculate vesting amount (95%)
        uint256 vestingAmount = (ben.totalAllocation * VESTING_PERCENT) / 100;

        uint256 elapsed = block.timestamp - tgeTime;

        // If vesting complete, return full allocation
        if (elapsed >= VESTING_DURATION) {
            return ben.totalAllocation;
        }

        // Linear vesting: tgeAmount + (vestingAmount * elapsed / duration)
        uint256 vestedFromSchedule = (vestingAmount * elapsed) / VESTING_DURATION;

        return tgeAmount + vestedFromSchedule;
    }
}
