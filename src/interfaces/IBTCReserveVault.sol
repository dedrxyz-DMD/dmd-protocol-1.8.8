// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBTCReserveVault {
    function totalWeightOf(address user) external view returns (uint256);
    function totalSystemWeight() external view returns (uint256);
    function getVestedWeight(address user) external view returns (uint256);
    function getTotalVestedWeight() external view returns (uint256);
    function getPositionVestedWeight(address user, uint256 positionId) external view returns (uint256);
    function redeem(address user, uint256 positionId) external;
    function getPosition(address user, uint256 positionId) external view returns (uint256, uint256, uint256, uint256);
    function isUnlocked(address user, uint256 positionId) external view returns (bool);
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool);
    function getTotalLocked() external view returns (uint256);
    function TBTC() external view returns (address);
    function PDC() external view returns (address);
    function getActivePositionCount(address user) external view returns (uint256);
    function getActivePositions(address user) external view returns (uint256[] memory);
    function getTotalUsers() external view returns (uint256);
    function updateVestedWeightCache(uint256 startIndex, uint256 maxUsers) external returns (uint256, bool);
    function cachedTotalVestedWeight() external view returns (uint256);
    function lastWeightCacheUpdate() external view returns (uint256);
    function requestEarlyUnlock(uint256 positionId) external;
    function cancelEarlyUnlock(uint256 positionId) external;
    function earlyUnlockRequestTime(address user, uint256 positionId) external view returns (uint256);
    function getEarlyUnlockStatus(address user, uint256 positionId) external view returns (bool requested, uint256 readyTime, bool isReady);
    function EARLY_UNLOCK_DELAY() external view returns (uint256);
}
