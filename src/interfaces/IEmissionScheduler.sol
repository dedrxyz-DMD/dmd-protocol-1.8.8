// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IEmissionScheduler {
    function claimEmission() external returns (uint256);
    function claimableNow() external view returns (uint256);
}
