// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMintDistributor {
    function getPositionDmdMinted(address user, uint256 positionId) external view returns (uint256);
    function clearPositionDmdMinted(address user, uint256 positionId) external;
}
