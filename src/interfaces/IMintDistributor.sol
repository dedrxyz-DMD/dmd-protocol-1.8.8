// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMintDistributor {
    function getPositionDMDMinted(address user, uint256 positionId) external view returns (uint256);
}
