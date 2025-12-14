// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";

/**
 * @title VestingContract
 * @notice Diamond Vesting Curve (DVC): 5% at TGE, 95% linear over 7 years
 * @dev Supports multiple beneficiaries with fixed allocations
 */
contract VestingContract {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error InvalidAmount();
    error InvalidBeneficiary();
    error AlreadyInitialized();
    error NotStarted();
    error NothingToClaim();
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant TGE_PERCENT = 5;
    uint256 public constant VESTING_PERCENT = 95;
    uint256 public constant VESTING_DURATION = 7 * 365 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    IDMDToken public immutable dmdToken;

    uint256 public tgeTime;
    bool public initialized;

    struct Beneficiary {
        uint256 totalAllocation;    // Total DMD allocated
        uint256 claimed;            // Amount already claimed
    }

    mapping(address => Beneficiary) public beneficiaries;
    address[] public beneficiaryList;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event VestingStarted(uint256 tgeTime);
    event Claimed(address indexed beneficiary, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, IDMDToken _dmdToken) {
        if (_owner == address(0) || address(_dmdToken) == address(0)) {
            revert InvalidBeneficiary();
        }
        owner = _owner;
        dmdToken = _dmdToken;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add beneficiary with allocation (before TGE)
     * @param beneficiary Beneficiary address
     * @param allocation Total DMD allocation
     */
    function addBeneficiary(address beneficiary, uint256 allocation) external {
        if (msg.sender != owner) revert Unauthorized();
        if (initialized) revert AlreadyInitialized();
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (allocation == 0) revert InvalidAmount();
        if (beneficiaries[beneficiary].totalAllocation != 0) revert AlreadyInitialized();

        beneficiaries[beneficiary] = Beneficiary({
            totalAllocation: allocation,
            claimed: 0
        });

        beneficiaryList.push(beneficiary);

        emit BeneficiaryAdded(beneficiary, allocation);
    }

    /**
     * @notice Start vesting (TGE)
     * @dev Can only be called once by owner
     */
    function startVesting() external {
        if (msg.sender != owner) revert Unauthorized();
        if (initialized) revert AlreadyInitialized();
        if (beneficiaryList.length == 0) revert InvalidBeneficiary();

        initialized = true;
        tgeTime = block.timestamp;

        emit VestingStarted(tgeTime);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim vested DMD
     * @dev Beneficiary calls to receive their vested tokens
     */
    function claim() external {
        if (!initialized) revert NotStarted();

        Beneficiary storage beneficiary = beneficiaries[msg.sender];
        if (beneficiary.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 vested = _vestedAmount(msg.sender);
        uint256 claimable = vested - beneficiary.claimed;

        if (claimable == 0) revert NothingToClaim();

        beneficiary.claimed += claimable;

        bool success = dmdToken.transfer(msg.sender, claimable);
        if (!success) revert TransferFailed();

        emit Claimed(msg.sender, claimable);
    }

    /**
     * @notice Claim on behalf of beneficiary (anyone can trigger)
     * @param beneficiary Address to claim for
     */
    function claimFor(address beneficiary) external {
        if (!initialized) revert NotStarted();

        Beneficiary storage ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 vested = _vestedAmount(beneficiary);
        uint256 claimable = vested - ben.claimed;

        if (claimable == 0) revert NothingToClaim();

        ben.claimed += claimable;

        bool success = dmdToken.transfer(beneficiary, claimable);
        if (!success) revert TransferFailed();

        emit Claimed(beneficiary, claimable);
    }

    /**
     * @notice Batch claim for multiple beneficiaries
     */
    function claimMultiple(address[] calldata _beneficiaries) external {
        if (!initialized) revert NotStarted();

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            Beneficiary storage ben = beneficiaries[beneficiary];

            if (ben.totalAllocation == 0) continue;

            uint256 vested = _vestedAmount(beneficiary);
            uint256 claimable = vested - ben.claimed;

            if (claimable == 0) continue;

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
        if (!initialized) return 0;
        
        Beneficiary memory ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) return 0;

        uint256 vested = _vestedAmount(beneficiary);
        return vested > ben.claimed ? vested - ben.claimed : 0;
    }

    /**
     * @notice Get vested amount (total unlocked so far)
     */
    function getVested(address beneficiary) external view returns (uint256) {
        if (!initialized) return 0;
        return _vestedAmount(beneficiary);
    }

    /**
     * @notice Get beneficiary details
     */
    function getBeneficiary(address beneficiary) 
        external 
        view 
        returns (
            uint256 totalAllocation,
            uint256 claimed,
            uint256 vested,
            uint256 claimable
        ) 
    {
        Beneficiary memory ben = beneficiaries[beneficiary];
        totalAllocation = ben.totalAllocation;
        claimed = ben.claimed;
        
        if (initialized) {
            vested = _vestedAmount(beneficiary);
            claimable = vested > claimed ? vested - claimed : 0;
        }
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

    /*//////////////////////////////////////////////////////////////
                        INTERNAL CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    function _vestedAmount(address beneficiary) internal view returns (uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        
        // Calculate TGE amount (5%)
        uint256 tgeAmount = (ben.totalAllocation * TGE_PERCENT) / 100;

        // If vesting hasn't started, return 0
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
