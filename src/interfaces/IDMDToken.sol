// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IDMDToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    function uniqueHolderCount() external view returns (uint256);
}
