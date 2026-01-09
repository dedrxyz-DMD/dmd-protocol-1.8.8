// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDMDToken} from "./interfaces/IDMDToken.sol";

/// @title VestingContract - Diamond Vesting Curve: 5% TGE, 95% linear over 7 years
/// @dev Fully decentralized, mints directly from DMDToken (no external funding needed)
/// @dev Beneficiaries and allocations set immutably at deployment
contract VestingContract {
    error InvalidBeneficiary();
    error InvalidAmount();
    error NothingToClaim();
    error ArrayLengthMismatch();

    uint256 public constant TGE_PERCENT = 5;
    uint256 public constant VESTING_PERCENT = 95;
    uint256 public constant VESTING_DURATION = 7 * 365 days;

    IDMDToken public immutable DMD_TOKEN;
    uint256 public immutable TGE_TIME;
    uint256 public immutable TOTAL_ALLOCATION;

    struct Beneficiary {
        uint256 totalAllocation;
        uint256 claimed;
    }

    mapping(address => Beneficiary) public beneficiaries;
    address[] public beneficiaryList;

    event Claimed(address indexed beneficiary, uint256 amount);

    constructor(IDMDToken _dmdToken, address[] memory _beneficiaries, uint256[] memory _allocations) {
        if (address(_dmdToken) == address(0) || _beneficiaries.length == 0) revert InvalidBeneficiary();
        if (_beneficiaries.length != _allocations.length) revert ArrayLengthMismatch();

        DMD_TOKEN = _dmdToken;
        TGE_TIME = block.timestamp;

        uint256 total = 0;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            if (_beneficiaries[i] == address(0)) revert InvalidBeneficiary();
            if (_allocations[i] == 0) revert InvalidAmount();
            if (beneficiaries[_beneficiaries[i]].totalAllocation != 0) revert InvalidBeneficiary();

            beneficiaries[_beneficiaries[i]] = Beneficiary({totalAllocation: _allocations[i], claimed: 0});
            beneficiaryList.push(_beneficiaries[i]);
            total += _allocations[i];
        }
        TOTAL_ALLOCATION = total;
    }

    /// @notice Claim vested DMD (mints directly, no external funding needed)
    function claim() external {
        Beneficiary storage ben = beneficiaries[msg.sender];
        if (ben.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 claimable = _vestedAmount(msg.sender) - ben.claimed;
        if (claimable == 0) revert NothingToClaim();

        ben.claimed += claimable;
        DMD_TOKEN.mint(msg.sender, claimable);
        emit Claimed(msg.sender, claimable);
    }

    /// @notice Claim on behalf of beneficiary (anyone can trigger)
    function claimFor(address beneficiary) external {
        Beneficiary storage ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) revert InvalidBeneficiary();

        uint256 claimable = _vestedAmount(beneficiary) - ben.claimed;
        if (claimable == 0) revert NothingToClaim();

        ben.claimed += claimable;
        DMD_TOKEN.mint(beneficiary, claimable);
        emit Claimed(beneficiary, claimable);
    }

    function getClaimable(address beneficiary) external view returns (uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0) return 0;
        uint256 vested = _vestedAmount(beneficiary);
        return vested > ben.claimed ? vested - ben.claimed : 0;
    }

    function getVested(address beneficiary) external view returns (uint256) { return _vestedAmount(beneficiary); }

    function getBeneficiary(address beneficiary) external view returns (uint256, uint256, uint256, uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        uint256 vested = _vestedAmount(beneficiary);
        return (ben.totalAllocation, ben.claimed, vested, vested > ben.claimed ? vested - ben.claimed : 0);
    }

    function getAllBeneficiaries() external view returns (address[] memory) { return beneficiaryList; }
    function getBeneficiaryCount() external view returns (uint256) { return beneficiaryList.length; }

    function _vestedAmount(address beneficiary) internal view returns (uint256) {
        Beneficiary memory ben = beneficiaries[beneficiary];
        if (ben.totalAllocation == 0 || block.timestamp < TGE_TIME) return 0;

        uint256 tgeAmount = (ben.totalAllocation * TGE_PERCENT) / 100;
        if (block.timestamp == TGE_TIME) return tgeAmount;

        uint256 elapsed = block.timestamp - TGE_TIME;
        if (elapsed >= VESTING_DURATION) return ben.totalAllocation;

        uint256 vestingAmount = (ben.totalAllocation * VESTING_PERCENT) / 100;
        return tgeAmount + (vestingAmount * elapsed) / VESTING_DURATION;
    }
}
