// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/VestingContract.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract VestingContractTest is Test {
    VestingContract public vesting;
    MockDMDToken public dmdToken;

    address public owner;
    address public foundation;
    address public founders;
    address public developers;
    address public airdrop;
    address public partners;

    uint256 constant FOUNDATION_ALLOCATION = 1_620_000e18;
    uint256 constant FOUNDERS_ALLOCATION = 900_000e18;
    uint256 constant DEVELOPERS_ALLOCATION = 360_000e18;
    uint256 constant AIRDROP_ALLOCATION = 360_000e18;
    uint256 constant PARTNERS_ALLOCATION = 360_000e18;

    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event VestingStarted(uint256 tgeTime);
    event Claimed(address indexed beneficiary, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        foundation = makeAddr("foundation");
        founders = makeAddr("founders");
        developers = makeAddr("developers");
        airdrop = makeAddr("airdrop");
        partners = makeAddr("partners");

        dmdToken = new MockDMDToken();

        vm.prank(owner);
        vesting = new VestingContract(owner, IDMDToken(address(dmdToken)));
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(vesting.owner(), owner);
        assertEq(address(vesting.dmdToken()), address(dmdToken));
        assertEq(vesting.TGE_PERCENT(), 5);
        assertEq(vesting.VESTING_PERCENT(), 95);
        assertEq(vesting.VESTING_DURATION(), 7 * 365 days);
        assertFalse(vesting.initialized());
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        new VestingContract(address(0), IDMDToken(address(dmdToken)));
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        new VestingContract(owner, IDMDToken(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                          BENEFICIARY ADDITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddBeneficiary_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit BeneficiaryAdded(foundation, FOUNDATION_ALLOCATION);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        (uint256 totalAllocation, uint256 claimed, , ) = vesting.getBeneficiary(foundation);
        assertEq(totalAllocation, FOUNDATION_ALLOCATION);
        assertEq(claimed, 0);
    }

    function test_AddBeneficiary_MultipleBeneficiaries() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vesting.addBeneficiary(founders, FOUNDERS_ALLOCATION);
        vesting.addBeneficiary(developers, DEVELOPERS_ALLOCATION);
        vesting.addBeneficiary(airdrop, AIRDROP_ALLOCATION);
        vesting.addBeneficiary(partners, PARTNERS_ALLOCATION);
        vm.stopPrank();

        assertEq(vesting.getBeneficiaryCount(), 5);
        
        address[] memory beneficiaries = vesting.getAllBeneficiaries();
        assertEq(beneficiaries.length, 5);
        assertEq(beneficiaries[0], foundation);
        assertEq(beneficiaries[4], partners);
    }

    function test_AddBeneficiary_RevertsOnUnauthorized() public {
        vm.prank(foundation);
        vm.expectRevert(VestingContract.Unauthorized.selector);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
    }

    function test_AddBeneficiary_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        vesting.addBeneficiary(address(0), FOUNDATION_ALLOCATION);
    }

    function test_AddBeneficiary_RevertsOnZeroAllocation() public {
        vm.prank(owner);
        vm.expectRevert(VestingContract.InvalidAmount.selector);
        vesting.addBeneficiary(foundation, 0);
    }

    function test_AddBeneficiary_RevertsAfterInit() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vesting.startVesting();

        vm.expectRevert(VestingContract.AlreadyInitialized.selector);
        vesting.addBeneficiary(founders, FOUNDERS_ALLOCATION);
        vm.stopPrank();
    }

    function test_AddBeneficiary_RevertsOnDuplicate() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.expectRevert(VestingContract.AlreadyInitialized.selector);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          VESTING START TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartVesting_Success() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        uint256 tgeTime = block.timestamp;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit VestingStarted(tgeTime);
        vesting.startVesting();

        assertTrue(vesting.initialized());
        assertEq(vesting.tgeTime(), tgeTime);
    }

    function test_StartVesting_RevertsOnUnauthorized() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(foundation);
        vm.expectRevert(VestingContract.Unauthorized.selector);
        vesting.startVesting();
    }

    function test_StartVesting_RevertsOnAlreadyInitialized() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vesting.startVesting();

        vm.expectRevert(VestingContract.AlreadyInitialized.selector);
        vesting.startVesting();
        vm.stopPrank();
    }

    function test_StartVesting_RevertsOnNoBeneficiaries() public {
        vm.prank(owner);
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        vesting.startVesting();
    }

    /*//////////////////////////////////////////////////////////////
                          VESTING CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_VestedAmount_BeforeTGE() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        uint256 vested = vesting.getVested(foundation);
        assertEq(vested, 0);
    }

    function test_VestedAmount_AtTGE() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        uint256 vested = vesting.getVested(foundation);
        uint256 expectedTGE = (FOUNDATION_ALLOCATION * 5) / 100;
        assertEq(vested, expectedTGE);
    }

    function test_VestedAmount_OneYear() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + 365 days);

        uint256 vested = vesting.getVested(foundation);
        
        // TGE: 5% + 1 year of 95% over 7 years
        uint256 tgeAmount = (FOUNDATION_ALLOCATION * 5) / 100;
        uint256 vestingAmount = (FOUNDATION_ALLOCATION * 95) / 100;
        uint256 oneYearVested = (vestingAmount * 365 days) / (7 * 365 days);
        uint256 expected = tgeAmount + oneYearVested;

        assertApproxEqAbs(vested, expected, 1e18);
    }

    function test_VestedAmount_HalfwayThrough() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        // 3.5 years
        vm.warp(block.timestamp + (7 * 365 days / 2));

        uint256 vested = vesting.getVested(foundation);
        
        // Should be approximately 52.5% (5% + 47.5%)
        uint256 expectedPercent = 525; // 52.5%
        uint256 expected = (FOUNDATION_ALLOCATION * expectedPercent) / 1000;

        assertApproxEqAbs(vested, expected, 1e18);
    }

    function test_VestedAmount_FullyVested() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + (7 * 365 days));

        uint256 vested = vesting.getVested(foundation);
        assertEq(vested, FOUNDATION_ALLOCATION);
    }

    function test_VestedAmount_BeyondFullVesting() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + (10 * 365 days));

        uint256 vested = vesting.getVested(foundation);
        assertEq(vested, FOUNDATION_ALLOCATION);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Claim_RevertsBeforeStart() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(foundation);
        vm.expectRevert(VestingContract.NotStarted.selector);
        vesting.claim();
    }

    function test_Claim_TGEAmount() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        // Fund vesting contract
        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        uint256 expectedTGE = (FOUNDATION_ALLOCATION * 5) / 100;

        vm.prank(foundation);
        vm.expectEmit(true, false, false, true);
        emit Claimed(foundation, expectedTGE);
        vesting.claim();

        assertEq(dmdToken.balanceOf(foundation), expectedTGE);

        (uint256 totalAllocation, uint256 claimed, , ) = vesting.getBeneficiary(foundation);
        assertEq(claimed, expectedTGE);
    }

    function test_Claim_AfterOneYear() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + 365 days);

        vm.prank(foundation);
        vesting.claim();

        uint256 tgeAmount = (FOUNDATION_ALLOCATION * 5) / 100;
        uint256 vestingAmount = (FOUNDATION_ALLOCATION * 95) / 100;
        uint256 oneYearVested = (vestingAmount * 365 days) / (7 * 365 days);
        uint256 expected = tgeAmount + oneYearVested;

        assertApproxEqAbs(dmdToken.balanceOf(foundation), expected, 1e18);
    }

    function test_Claim_MultipleClaims() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        // Claim at TGE
        vm.prank(foundation);
        vesting.claim();
        uint256 balance1 = dmdToken.balanceOf(foundation);

        // Claim after 1 year
        vm.warp(block.timestamp + 365 days);
        vm.prank(foundation);
        vesting.claim();
        uint256 balance2 = dmdToken.balanceOf(foundation);

        // Claim after another year
        vm.warp(block.timestamp + 365 days);
        vm.prank(foundation);
        vesting.claim();
        uint256 balance3 = dmdToken.balanceOf(foundation);

        assertGt(balance2, balance1);
        assertGt(balance3, balance2);
    }

    function test_Claim_RevertsOnNothingToClaim() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.prank(foundation);
        vesting.claim();

        // Try to claim again immediately
        vm.prank(foundation);
        vm.expectRevert(VestingContract.NothingToClaim.selector);
        vesting.claim();
    }

    function test_Claim_RevertsOnInvalidBeneficiary() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.prank(founders); // Not a beneficiary
        vm.expectRevert(VestingContract.InvalidBeneficiary.selector);
        vesting.claim();
    }

    function test_Claim_FullAllocationOverTime() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        // Claim over 7 years in yearly increments
        for (uint256 i = 0; i < 8; i++) {
            if (i > 0) {
                vm.warp(block.timestamp + 365 days);
            }
            
            uint256 claimable = vesting.getClaimable(foundation);
            if (claimable > 0) {
                vm.prank(foundation);
                vesting.claim();
            }
        }

        assertApproxEqAbs(dmdToken.balanceOf(foundation), FOUNDATION_ALLOCATION, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimFor_Success() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        uint256 expectedTGE = (FOUNDATION_ALLOCATION * 5) / 100;

        // Anyone can call claimFor
        vesting.claimFor(foundation);

        assertEq(dmdToken.balanceOf(foundation), expectedTGE);
    }

    function test_ClaimFor_Permissionless() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        // Random address can trigger claim
        vm.prank(founders);
        vesting.claimFor(foundation);

        uint256 expectedTGE = (FOUNDATION_ALLOCATION * 5) / 100;
        assertEq(dmdToken.balanceOf(foundation), expectedTGE);
    }

    /*//////////////////////////////////////////////////////////////
                          BATCH CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimMultiple_Success() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vesting.addBeneficiary(founders, FOUNDERS_ALLOCATION);
        vesting.addBeneficiary(developers, DEVELOPERS_ALLOCATION);
        vm.stopPrank();

        uint256 totalAllocation = FOUNDATION_ALLOCATION + FOUNDERS_ALLOCATION + DEVELOPERS_ALLOCATION;
        dmdToken.mint(address(vesting), totalAllocation);

        vm.prank(owner);
        vesting.startVesting();

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = foundation;
        beneficiaries[1] = founders;
        beneficiaries[2] = developers;

        vesting.claimMultiple(beneficiaries);

        uint256 foundationTGE = (FOUNDATION_ALLOCATION * 5) / 100;
        uint256 foundersTGE = (FOUNDERS_ALLOCATION * 5) / 100;
        uint256 developersTGE = (DEVELOPERS_ALLOCATION * 5) / 100;

        assertEq(dmdToken.balanceOf(foundation), foundationTGE);
        assertEq(dmdToken.balanceOf(founders), foundersTGE);
        assertEq(dmdToken.balanceOf(developers), developersTGE);
    }

    function test_ClaimMultiple_SkipsNothingToClaim() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);
        vesting.addBeneficiary(founders, FOUNDERS_ALLOCATION);
        vm.stopPrank();

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION + FOUNDERS_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        // Claim foundation individually first
        vm.prank(foundation);
        vesting.claim();

        // Batch claim including foundation (should skip)
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = foundation;
        beneficiaries[1] = founders;

        vesting.claimMultiple(beneficiaries);

        // Founders should have claimed, foundation balance unchanged
        uint256 foundationTGE = (FOUNDATION_ALLOCATION * 5) / 100;
        uint256 foundersTGE = (FOUNDERS_ALLOCATION * 5) / 100;

        assertEq(dmdToken.balanceOf(foundation), foundationTGE);
        assertEq(dmdToken.balanceOf(founders), foundersTGE);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetClaimable_BeforeStart() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        assertEq(vesting.getClaimable(foundation), 0);
    }

    function test_GetClaimable_AtTGE() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        uint256 expectedTGE = (FOUNDATION_ALLOCATION * 5) / 100;
        assertEq(vesting.getClaimable(foundation), expectedTGE);
    }

    function test_GetClaimable_AfterClaim() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.prank(foundation);
        vesting.claim();

        assertEq(vesting.getClaimable(foundation), 0);

        // After time passes
        vm.warp(block.timestamp + 365 days);
        assertGt(vesting.getClaimable(foundation), 0);
    }

    function test_GetBeneficiary() public {
        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        dmdToken.mint(address(vesting), FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + 365 days);

        (
            uint256 totalAllocation,
            uint256 claimed,
            uint256 vested,
            uint256 claimable
        ) = vesting.getBeneficiary(foundation);

        assertEq(totalAllocation, FOUNDATION_ALLOCATION);
        assertEq(claimed, 0);
        assertGt(vested, 0);
        assertGt(claimable, 0);
        assertEq(vested, claimable);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_VestedAmount(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 10 * 365 days);

        vm.prank(owner);
        vesting.addBeneficiary(foundation, FOUNDATION_ALLOCATION);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + timeElapsed);

        uint256 vested = vesting.getVested(foundation);

        // Should never exceed total allocation
        assertLe(vested, FOUNDATION_ALLOCATION);

        // Should be at least TGE amount if any time has passed
        if (timeElapsed > 0) {
            uint256 tgeAmount = (FOUNDATION_ALLOCATION * 5) / 100;
            assertGe(vested, tgeAmount);
        }

        // Should be full amount after 7 years
        if (timeElapsed >= 7 * 365 days) {
            assertEq(vested, FOUNDATION_ALLOCATION);
        }
    }

    function testFuzz_Claim(uint256 allocation, uint256 timeElapsed) public {
        allocation = bound(allocation, 1e18, 10_000_000e18);
        timeElapsed = bound(timeElapsed, 0, 7 * 365 days);

        vm.prank(owner);
        vesting.addBeneficiary(foundation, allocation);

        dmdToken.mint(address(vesting), allocation);

        vm.prank(owner);
        vesting.startVesting();

        vm.warp(block.timestamp + timeElapsed);

        uint256 claimable = vesting.getClaimable(foundation);
        
        if (claimable > 0) {
            vm.prank(foundation);
            vesting.claim();

            assertEq(dmdToken.balanceOf(foundation), claimable);
        }
    }
}