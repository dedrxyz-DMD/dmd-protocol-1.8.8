// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title IProtocolDefenseConsensus - Interface for PDC adapter management
/// @notice PDC manages external BTC bridge adapters (e.g., tBTC)
interface IProtocolDefenseConsensus {
    /// @notice Check if an adapter is active (approved, not paused, not deprecated)
    /// @param adapter Adapter address to check
    /// @return True if adapter can receive deposits
    function isAdapterActive(address adapter) external view returns (bool);

    /// @notice Check if an adapter is approved
    /// @param adapter Adapter address to check
    /// @return True if adapter has been approved
    function approvedAdapters(address adapter) external view returns (bool);

    /// @notice Check if an adapter is paused
    /// @param adapter Adapter address to check
    /// @return True if adapter is currently paused
    function pausedAdapters(address adapter) external view returns (bool);

    /// @notice Check if an adapter is deprecated
    /// @param adapter Adapter address to check
    /// @return True if adapter has been deprecated
    function deprecatedAdapters(address adapter) external view returns (bool);

    /// @notice Check if PDC governance is activated
    /// @return True if PDC can accept proposals
    function activated() external view returns (bool);
}
