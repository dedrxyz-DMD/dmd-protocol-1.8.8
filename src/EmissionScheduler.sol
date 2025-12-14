// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title EmissionScheduler
 * @notice Manages year-based DMD emissions with 0.75 annual decay
 * @dev Linear release per second, 14.4M cumulative cap, immutable schedule
 */
contract EmissionScheduler {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotStarted();
    error AlreadyStarted();
    error Unauthorized();
    error EmissionCapReached();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant YEAR_1_EMISSION = 3_600_000e18;
    uint256 public constant DECAY_NUMERATOR = 75;
    uint256 public constant DECAY_DENOMINATOR = 100;
    uint256 public constant EMISSION_CAP = 14_400_000e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    address public immutable mintDistributor;

    uint256 public emissionStartTime;
    uint256 public totalEmitted;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event EmissionStarted(uint256 startTime);
    event EmissionClaimed(uint256 amount, uint256 year);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _mintDistributor) {
        if (_owner == address(0) || _mintDistributor == address(0)) {
            revert Unauthorized();
        }
        owner = _owner;
        mintDistributor = _mintDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Start emission schedule (one-time only)
     */
    function startEmissions() external {
        if (msg.sender != owner) revert Unauthorized();
        if (emissionStartTime != 0) revert AlreadyStarted();

        emissionStartTime = block.timestamp;
        emit EmissionStarted(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          EMISSION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim available emissions (called by MintDistributor)
     * @return amount Claimable emission amount
     */
    function claimEmission() external returns (uint256 amount) {
        if (msg.sender != mintDistributor) revert Unauthorized();
        if (emissionStartTime == 0) revert NotStarted();

        amount = _claimableNow();
        if (amount == 0) return 0;

        totalEmitted += amount;
        
        uint256 currentYear = _getCurrentYear();
        emit EmissionClaimed(amount, currentYear);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get currently claimable emission amount
     */
    function claimableNow() external view returns (uint256) {
        if (emissionStartTime == 0) return 0;
        return _claimableNow();
    }

    /**
     * @notice Get current emission year (0-indexed)
     */
    function getCurrentYear() external view returns (uint256) {
        if (emissionStartTime == 0) return 0;
        return _getCurrentYear();
    }

    /**
     * @notice Get total emission for a specific year
     */
    function getYearEmission(uint256 year) public pure returns (uint256) {
        if (year == 0) return YEAR_1_EMISSION;
        
        uint256 emission = YEAR_1_EMISSION;
        for (uint256 i = 0; i < year; i++) {
            emission = (emission * DECAY_NUMERATOR) / DECAY_DENOMINATOR;
        }
        return emission;
    }

    /**
     * @notice Get emission rate per second for current year
     */
    function currentEmissionRate() external view returns (uint256) {
        if (emissionStartTime == 0) return 0;
        
        uint256 year = _getCurrentYear();
        uint256 yearEmission = getYearEmission(year);
        return yearEmission / SECONDS_PER_YEAR;
    }

    /**
     * @notice Check if emission cap has been reached
     */
    function capReached() public view returns (bool) {
        return totalEmitted >= EMISSION_CAP;
    }

    /**
     * @notice Get total theoretical emissions up to current time
     */
    function totalTheoreticalEmissions() external view returns (uint256) {
        if (emissionStartTime == 0) return 0;
        return _calculateTotalEmittedUpToNow();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    function _claimableNow() internal view returns (uint256) {
        if (capReached()) return 0;

        uint256 theoretical = _calculateTotalEmittedUpToNow();
        uint256 claimable = theoretical > totalEmitted 
            ? theoretical - totalEmitted 
            : 0;

        // Enforce cap
        if (totalEmitted + claimable > EMISSION_CAP) {
            claimable = EMISSION_CAP - totalEmitted;
        }

        return claimable;
    }

    function _getCurrentYear() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - emissionStartTime;
        return elapsed / SECONDS_PER_YEAR;
    }

    function _calculateTotalEmittedUpToNow() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - emissionStartTime;
        uint256 totalEmission = 0;

        uint256 currentYear = 0;
        uint256 remainingTime = elapsed;

        // Sum complete years
        while (remainingTime >= SECONDS_PER_YEAR) {
            uint256 yearEmission = getYearEmission(currentYear);
            totalEmission += yearEmission;
            
            remainingTime -= SECONDS_PER_YEAR;
            currentYear++;

            // Stop if cap reached
            if (totalEmission >= EMISSION_CAP) {
                return EMISSION_CAP;
            }
        }

        // Add partial year
        if (remainingTime > 0) {
            uint256 yearEmission = getYearEmission(currentYear);
            uint256 partialEmission = (yearEmission * remainingTime) / SECONDS_PER_YEAR;
            totalEmission += partialEmission;
        }

        // Enforce cap
        if (totalEmission > EMISSION_CAP) {
            return EMISSION_CAP;
        }

        return totalEmission;
    }
}