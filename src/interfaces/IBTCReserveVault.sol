// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IBTCReserveVault
 * @notice Interface for BTCReserveVault contract (tBTC only)
 * @dev Used by MintDistributor and RedemptionEngine
 */
interface IBTCReserveVault {
    /// @notice Get raw total weight for a user (not vested)
    function totalWeightOf(address user) external view returns (uint256);

    /// @notice Get raw total system weight (not vested)
    function totalSystemWeight() external view returns (uint256);

    /// @notice Get vested weight for a user (flash loan protected)
    function getVestedWeight(address user) external view returns (uint256);

    /// @notice Redeem position (RedemptionEngine only)
    function redeem(address user, uint256 positionId) external;

    /// @notice Get position details
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight
        );

    /// @notice Check if position lock period has expired
    function isUnlocked(address user, uint256 positionId) external view returns (bool);

    /// @notice Check if position weight is fully vested
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool);

    /// @notice Get total locked tBTC
    function getTotalLocked() external view returns (uint256);
}
