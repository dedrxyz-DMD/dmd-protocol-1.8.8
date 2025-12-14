// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBTCReserveVault {
    function totalWeightOf(address user) external view returns (uint256);
    function totalSystemWeight() external view returns (uint256);
    function redeem(address user, uint256 positionId) external;
    function getPosition(address user, uint256 positionId) 
        external 
        view 
        returns (
            uint256 amount,
            uint256 lockMonths,
            uint256 lockTime,
            uint256 weight,
            uint256 unlockTime
        );
    function isUnlocked(address user, uint256 positionId) external view returns (bool);
}
