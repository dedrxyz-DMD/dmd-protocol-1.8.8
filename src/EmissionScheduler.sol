// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title EmissionScheduler - Year-based DMD emissions with 25% annual decay
/// @dev Fully decentralized, 14.4M cap, auto-starts at deployment
contract EmissionScheduler {
    error Unauthorized();

    uint256 public constant YEAR_1_EMISSION = 3_600_000e18;
    uint256 public constant DECAY_NUMERATOR = 75;
    uint256 public constant DECAY_DENOMINATOR = 100;
    uint256 public constant EMISSION_CAP = 14_400_000e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    address public immutable mintDistributor;
    uint256 public immutable emissionStartTime;
    uint256 public totalEmitted;

    event EmissionClaimed(uint256 amount, uint256 year);

    constructor(address _mintDistributor) {
        if (_mintDistributor == address(0)) revert Unauthorized();
        mintDistributor = _mintDistributor;
        emissionStartTime = block.timestamp;
    }

    function claimEmission() external returns (uint256 amount) {
        if (msg.sender != mintDistributor) revert Unauthorized();

        amount = _claimableNow();
        if (amount == 0) return 0;

        totalEmitted += amount;
        emit EmissionClaimed(amount, _getCurrentYear());
    }

    function claimableNow() external view returns (uint256) { return _claimableNow(); }
    function getCurrentYear() external view returns (uint256) { return _getCurrentYear(); }
    function capReached() public view returns (bool) { return totalEmitted >= EMISSION_CAP; }

    function getYearEmission(uint256 year) public pure returns (uint256) {
        uint256 emission = YEAR_1_EMISSION;
        for (uint256 i = 0; i < year; i++) {
            emission = (emission * DECAY_NUMERATOR) / DECAY_DENOMINATOR;
        }
        return emission;
    }

    function currentEmissionRate() external view returns (uint256) {
        return getYearEmission(_getCurrentYear()) / SECONDS_PER_YEAR;
    }

    function _claimableNow() internal view returns (uint256) {
        if (capReached()) return 0;

        uint256 theoretical = _calculateTotalEmittedUpToNow();
        uint256 claimable = theoretical > totalEmitted ? theoretical - totalEmitted : 0;

        if (totalEmitted + claimable > EMISSION_CAP) {
            claimable = EMISSION_CAP - totalEmitted;
        }
        return claimable;
    }

    function _getCurrentYear() internal view returns (uint256) {
        return (block.timestamp - emissionStartTime) / SECONDS_PER_YEAR;
    }

    function _calculateTotalEmittedUpToNow() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - emissionStartTime;
        uint256 totalEmission = 0;
        uint256 currentYear = 0;
        uint256 remainingTime = elapsed;

        while (remainingTime >= SECONDS_PER_YEAR) {
            totalEmission += getYearEmission(currentYear);
            remainingTime -= SECONDS_PER_YEAR;
            currentYear++;
            if (totalEmission >= EMISSION_CAP) return EMISSION_CAP;
        }

        if (remainingTime > 0) {
            totalEmission += (getYearEmission(currentYear) * remainingTime) / SECONDS_PER_YEAR;
        }

        return totalEmission > EMISSION_CAP ? EMISSION_CAP : totalEmission;
    }
}
