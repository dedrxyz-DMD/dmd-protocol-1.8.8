// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {VestingContract, IDMDToken} from "../src/VestingContract.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract VestingContractTest is Test {
    VestingContract public vesting;
    MockDMDToken public dmdToken;

    address public alice;
    address public bob;

    event Claimed(address indexed beneficiary, uint256 amount);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        dmdToken = new MockDMDToken();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = alice;
        beneficiaries[1] = bob;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 1000e18;
        allocations[1] = 2000e18;

        vesting = new VestingContract(IDMDToken(address(dmdToken)), beneficiaries, allocations);
    }

    function test_Constructor() public view {
        assertEq(address(vesting.DMD_TOKEN()), address(dmdToken));
        assertEq(vesting.TGE_TIME(), block.timestamp);
        assertEq(vesting.TOTAL_ALLOCATION(), 3000e18);
        assertEq(vesting.TGE_PERCENT(), 5);
        assertEq(vesting.VESTING_PERCENT(), 95);
        assertEq(vesting.VESTING_DURATION(), 7 * 365 days);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = alice;
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 1000e18;

        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        new VestingContract(IDMDToken(address(0)), beneficiaries, allocations);
    }

    function test_Constructor_RevertsOnEmptyBeneficiaries() public {
        address[] memory beneficiaries = new address[](0);
        uint256[] memory allocations = new uint256[](0);

        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        new VestingContract(IDMDToken(address(dmdToken)), beneficiaries, allocations);
    }

    function test_Constructor_RevertsOnArrayMismatch() public {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = alice;
        beneficiaries[1] = bob;
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 1000e18;

        vm.expectRevert(VestingContract.ArrayLengthMismatch.selector);
        new VestingContract(IDMDToken(address(dmdToken)), beneficiaries, allocations);
    }

    function test_Claim_TGE() public {
        // At TGE (deployment time), 5% should be claimable
        uint256 tgeAmount = (1000e18 * 5) / 100;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, tgeAmount);
        vesting.claim();

        assertEq(dmdToken.balanceOf(alice), tgeAmount);
    }

    function test_Claim_AfterFullVesting() public {
        // After 7 years, full allocation should be claimable
        vm.warp(block.timestamp + 7 * 365 days);

        vm.prank(alice);
        vesting.claim();

        assertEq(dmdToken.balanceOf(alice), 1000e18);
    }

    function test_Claim_HalfwayVesting() public {
        // After 3.5 years, should have TGE + half of vesting
        vm.warp(block.timestamp + (7 * 365 days) / 2);

        uint256 tgeAmount = (1000e18 * 5) / 100;
        uint256 vestingAmount = (1000e18 * 95) / 100;
        uint256 expected = tgeAmount + (vestingAmount / 2);

        vm.prank(alice);
        vesting.claim();

        assertApproxEqAbs(dmdToken.balanceOf(alice), expected, 1);
    }

    function test_Claim_RevertsOnNonBeneficiary() public {
        address charlie = makeAddr("charlie");

        vm.prank(charlie);
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        vesting.claim();
    }

    function test_Claim_RevertsOnNothingToClaim() public {
        vm.prank(alice);
        vesting.claim();

        // Try to claim again immediately
        vm.prank(alice);
        vm.expectRevert(VestingContract.NothingToClaim.selector);
        vesting.claim();
    }

    function test_ClaimFor() public {
        uint256 tgeAmount = (1000e18 * 5) / 100;

        vm.prank(bob);
        vesting.claimFor(alice);

        assertEq(dmdToken.balanceOf(alice), tgeAmount);
    }

    function test_GetClaimable() public view {
        uint256 tgeAmount = (1000e18 * 5) / 100;
        assertEq(vesting.getClaimable(alice), tgeAmount);
    }

    function test_GetVested() public {
        uint256 tgeAmount = (1000e18 * 5) / 100;
        assertEq(vesting.getVested(alice), tgeAmount);

        vm.warp(block.timestamp + 7 * 365 days);
        assertEq(vesting.getVested(alice), 1000e18);
    }

    function test_GetBeneficiary() public view {
        (uint256 total, uint256 claimed, uint256 vested, uint256 claimable) = vesting.getBeneficiary(alice);

        uint256 tgeAmount = (1000e18 * 5) / 100;
        assertEq(total, 1000e18);
        assertEq(claimed, 0);
        assertEq(vested, tgeAmount);
        assertEq(claimable, tgeAmount);
    }

    function test_GetAllBeneficiaries() public view {
        address[] memory beneficiaries = vesting.getAllBeneficiaries();
        assertEq(beneficiaries.length, 2);
        assertEq(beneficiaries[0], alice);
        assertEq(beneficiaries[1], bob);
    }

    function test_GetBeneficiaryCount() public view {
        assertEq(vesting.getBeneficiaryCount(), 2);
    }
}
