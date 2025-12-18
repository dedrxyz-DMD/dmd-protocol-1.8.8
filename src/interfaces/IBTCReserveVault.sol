// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IBTCReserveVault
 * @notice Interface for the tBTC Reserve Vault with flash loan protection
 */
interface IBTCReserveVault {
    /// @notice Get total max weight for a user (before vesting)
    function totalWeightOf(address user) external view returns (uint256);

    /// @notice Get total max system weight (before vesting)
    function totalSystemWeight() external view returns (uint256);

    /// @notice Get total tBTC locked
    function totalLocked() external view returns (uint256);

    /// @notice Redeem a position (callable only by RedemptionEngine)
    function redeem(address user, uint256 positionId) external;

    /// @notice Get position details
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (
            address btcAsset,
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight
        );

    /// @notice Check if position lock period has expired
    function isUnlocked(address user, uint256 positionId) external view returns (bool);

    /// @notice Get number of positions for a user
    function positionCount(address user) external view returns (uint256);

    // Flash loan protection functions

    /// @notice Get vested weight for a specific position
    function getPositionVestedWeight(address user, uint256 positionId) external view returns (uint256);

    /// @notice Get total vested weight for a user
    function getVestedWeight(address user) external view returns (uint256);

    /// @notice Check if position weight is fully vested
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool);

    /// @notice Get vesting status (percent and time remaining)
    function getVestingStatus(address user, uint256 positionId)
        external
        view
        returns (uint256 vestingPercent, uint256 timeToFullVest);
}
