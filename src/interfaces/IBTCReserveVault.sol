// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBTCReserveVault {
    function totalWeightOf(address user) external view returns (uint256);
    function totalSystemWeight() external view returns (uint256);
    function getVestedWeight(address user) external view returns (uint256);
    function redeem(address user, uint256 positionId) external;
    function getPosition(address user, uint256 positionId) external view returns (uint256, uint256, uint256, uint256);
    function isUnlocked(address user, uint256 positionId) external view returns (bool);
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool);
    function getTotalLocked() external view returns (uint256);
    function TBTC() external view returns (address);
}
