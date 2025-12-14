// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/EmissionScheduler.sol";

contract EmissionSchedulerTest is Test {
    EmissionScheduler public scheduler;

    address public owner;
    address public mintDistributor;
    address public alice;

    event EmissionStarted(uint256 startTime);
    event EmissionClaimed(uint256 amount, uint256 year);

    function setUp() public {
        owner = makeAddr("owner");
        mintDistributor = makeAddr("mintDistributor");
        alice = makeAddr("alice");

        vm.prank(owner);
        scheduler = new EmissionScheduler(owner, mintDistributor);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(scheduler.owner(), owner);
        assertEq(scheduler.mintDistributor(), mintDistributor);
        assertEq(scheduler.emissionStartTime(), 0);
        assertEq(scheduler.totalEmitted(), 0);
        assertEq(scheduler.YEAR_1_EMISSION(), 3_600_000e18);
        assertEq(scheduler.EMISSION_CAP(), 14_400_000e18);
        assertEq(scheduler.DECAY_NUMERATOR(), 75);
        assertEq(scheduler.DECAY_DENOMINATOR(), 100);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        new EmissionScheduler(address(0), mintDistributor);
    }

    function test_Constructor_RevertsOnZeroMintDistributor() public {
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        new EmissionScheduler(owner, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartEmissions_Success() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit EmissionStarted(startTime);
        scheduler.startEmissions();

        assertEq(scheduler.emissionStartTime(), startTime);
    }

    function test_StartEmissions_RevertsOnUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        scheduler.startEmissions();
    }

    function test_StartEmissions_RevertsOnAlreadyStarted() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.prank(owner);
        vm.expectRevert(EmissionScheduler.AlreadyStarted.selector);
        scheduler.startEmissions();
    }

    /*//////////////////////////////////////////////////////////////
                          YEAR EMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetYearEmission_Year0() public {
        assertEq(scheduler.getYearEmission(0), 3_600_000e18);
    }

    function test_GetYearEmission_Year1() public {
        uint256 year1 = scheduler.getYearEmission(1);
        assertEq(year1, 2_700_000e18); // 3.6M * 0.75
    }

    function test_GetYearEmission_Year2() public {
        uint256 year2 = scheduler.getYearEmission(2);
        assertEq(year2, 2_025_000e18); // 2.7M * 0.75
    }

    function test_GetYearEmission_Year3() public {
        uint256 year3 = scheduler.getYearEmission(3);
        assertEq(year3, 1_518_750e18); // 2.025M * 0.75
    }

    function test_GetYearEmission_DecaySequence() public {
        uint256 year0 = scheduler.getYearEmission(0);
        
        for (uint256 i = 1; i < 5; i++) {
            uint256 prevYear = scheduler.getYearEmission(i - 1);
            uint256 currentYear = scheduler.getYearEmission(i);
            
            // Verify 0.75 decay
            assertEq(currentYear, (prevYear * 75) / 100);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM EMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimEmission_RevertsWhenNotStarted() public {
        vm.prank(mintDistributor);
        vm.expectRevert(EmissionScheduler.NotStarted.selector);
        scheduler.claimEmission();
    }

    function test_ClaimEmission_RevertsOnUnauthorized() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.prank(alice);
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        scheduler.claimEmission();
    }

    function test_ClaimEmission_FirstSecond() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 1);

        uint256 expectedRate = 3_600_000e18 / 365 days;
        
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        assertApproxEqAbs(claimed, expectedRate, 1);
        assertEq(scheduler.totalEmitted(), claimed);
    }

    function test_ClaimEmission_OneDay() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 1 days);

        uint256 expectedEmission = (3_600_000e18 * 1 days) / 365 days;
        
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        assertApproxEqAbs(claimed, expectedEmission, 1e18);
        assertEq(scheduler.totalEmitted(), claimed);
    }

    function test_ClaimEmission_OneWeek() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 7 days);

        uint256 expectedEmission = (3_600_000e18 * 7 days) / 365 days;
        
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        assertApproxEqAbs(claimed, expectedEmission, 1e18);
    }

    function test_ClaimEmission_FullYear() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 365 days);

        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        assertApproxEqAbs(claimed, 3_600_000e18, 1e18);
        assertEq(scheduler.getCurrentYear(), 1);
    }

    function test_ClaimEmission_MultipleClaims() public {
        vm.prank(owner);
        scheduler.startEmissions();

        // Claim after 1 day
        vm.warp(block.timestamp + 1 days);
        vm.prank(mintDistributor);
        uint256 claim1 = scheduler.claimEmission();

        // Claim after another day
        vm.warp(block.timestamp + 1 days);
        vm.prank(mintDistributor);
        uint256 claim2 = scheduler.claimEmission();

        assertGt(claim2, 0);
        assertEq(scheduler.totalEmitted(), claim1 + claim2);
    }

    function test_ClaimEmission_NoDoubleClaim() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 1 days);

        vm.prank(mintDistributor);
        uint256 claim1 = scheduler.claimEmission();

        // Immediate second claim should return 0
        vm.prank(mintDistributor);
        uint256 claim2 = scheduler.claimEmission();

        assertGt(claim1, 0);
        assertEq(claim2, 0);
    }

    function test_ClaimEmission_Year2Transition() public {
        vm.prank(owner);
        scheduler.startEmissions();

        // Claim full year 1
        vm.warp(block.timestamp + 365 days);
        vm.prank(mintDistributor);
        scheduler.claimEmission();

        // Move into year 2
        vm.warp(block.timestamp + 1 days);
        vm.prank(mintDistributor);
        uint256 claim = scheduler.claimEmission();

        uint256 year2Rate = 2_700_000e18 / 365 days;
        assertApproxEqAbs(claim, year2Rate, 1);
        assertEq(scheduler.getCurrentYear(), 2);
    }

    function test_ClaimEmission_MultipleYears() public {
        vm.prank(owner);
        scheduler.startEmissions();

        // Fast forward 3 years
        vm.warp(block.timestamp + (3 * 365 days));

        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        // Year 0: 3.6M, Year 1: 2.7M, Year 2: 2.025M = 8.325M
        uint256 expected = 3_600_000e18 + 2_700_000e18 + 2_025_000e18;
        assertApproxEqAbs(claimed, expected, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          CAP ENFORCEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimEmission_EnforcesCap() public {
        vm.prank(owner);
        scheduler.startEmissions();

        // Fast forward 20 years (way past cap)
        vm.warp(block.timestamp + (20 * 365 days));

        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        assertEq(claimed, scheduler.EMISSION_CAP());
        assertTrue(scheduler.capReached());
    }

    function test_ClaimEmission_NothingAfterCap() public {
        vm.prank(owner);
        scheduler.startEmissions();

        // Reach cap
        vm.warp(block.timestamp + (20 * 365 days));
        vm.prank(mintDistributor);
        scheduler.claimEmission();

        // Try to claim more
        vm.warp(block.timestamp + 365 days);
        vm.prank(mintDistributor);
        uint256 claim = scheduler.claimEmission();

        assertEq(claim, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimableNow_BeforeStart() public {
        assertEq(scheduler.claimableNow(), 0);
    }

    function test_ClaimableNow_AfterStart() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 1 days);

        uint256 claimable = scheduler.claimableNow();
        uint256 expected = (3_600_000e18 * 1 days) / 365 days;

        assertApproxEqAbs(claimable, expected, 1e18);
    }

    function test_ClaimableNow_AfterClaim() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 1 days);
        vm.prank(mintDistributor);
        scheduler.claimEmission();

        // Immediately after claim
        assertEq(scheduler.claimableNow(), 0);

        // After more time
        vm.warp(block.timestamp + 1 days);
        assertGt(scheduler.claimableNow(), 0);
    }

    function test_GetCurrentYear() public {
        vm.prank(owner);
        scheduler.startEmissions();

        assertEq(scheduler.getCurrentYear(), 0);

        vm.warp(block.timestamp + 364 days);
        assertEq(scheduler.getCurrentYear(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(scheduler.getCurrentYear(), 1);

        vm.warp(block.timestamp + 365 days);
        assertEq(scheduler.getCurrentYear(), 2);
    }

    function test_CurrentEmissionRate() public {
        vm.prank(owner);
        scheduler.startEmissions();

        uint256 rate = scheduler.currentEmissionRate();
        uint256 expected = 3_600_000e18 / 365 days;

        assertEq(rate, expected);
    }

    function test_CurrentEmissionRate_Year2() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + 365 days);

        uint256 rate = scheduler.currentEmissionRate();
        uint256 expected = 2_700_000e18 / 365 days;

        assertEq(rate, expected);
    }

    function test_TotalTheoreticalEmissions() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + (365 days / 2)); // Half year

        uint256 theoretical = scheduler.totalTheoreticalEmissions();
        uint256 expected = 3_600_000e18 / 2;

        assertApproxEqAbs(theoretical, expected, 1e18);
    }

    function test_CapReached() public {
        vm.prank(owner);
        scheduler.startEmissions();

        assertFalse(scheduler.capReached());

        vm.warp(block.timestamp + (20 * 365 days));
        vm.prank(mintDistributor);
        scheduler.claimEmission();

        assertTrue(scheduler.capReached());
    }

    /*//////////////////////////////////////////////////////////////
                          EMISSION ACCURACY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmissionAccuracy_QuarterYear() public {
        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + (365 days / 4));

        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        uint256 expected = 3_600_000e18 / 4;
        assertApproxEqAbs(claimed, expected, 1e18);
    }

    function test_EmissionAccuracy_MultipleSmallClaims() public {
        vm.prank(owner);
        scheduler.startEmissions();

        uint256 totalClaimed = 0;

        // Claim 10 times over 10 days
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(mintDistributor);
            uint256 claimed = scheduler.claimEmission();
            totalClaimed += claimed;
        }

        uint256 expected = (3_600_000e18 * 10 days) / 365 days;
        assertApproxEqAbs(totalClaimed, expected, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ClaimEmission(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 1, 365 days);

        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();

        uint256 expected = (3_600_000e18 * timeElapsed) / 365 days;
        assertApproxEqAbs(claimed, expected, 1e18);
    }

    function testFuzz_GetYearEmission(uint256 year) public {
        year = bound(year, 0, 20);

        uint256 emission = scheduler.getYearEmission(year);

        if (year == 0) {
            assertEq(emission, 3_600_000e18);
        } else {
            uint256 prevEmission = scheduler.getYearEmission(year - 1);
            assertEq(emission, (prevEmission * 75) / 100);
        }
    }

    function testFuzz_CurrentYear(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 10 * 365 days);

        vm.prank(owner);
        scheduler.startEmissions();

        vm.warp(block.timestamp + timeElapsed);

        uint256 currentYear = scheduler.getCurrentYear();
        uint256 expectedYear = timeElapsed / 365 days;

        assertEq(currentYear, expectedYear);
    }
}