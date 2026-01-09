// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {EmissionScheduler} from "../src/EmissionScheduler.sol";

contract EmissionSchedulerTest is Test {
    EmissionScheduler public scheduler;
    address public mintDistributor;
    address public alice;

    event EmissionClaimed(uint256 amount, uint256 year);

    function setUp() public {
        mintDistributor = makeAddr("mintDistributor");
        alice = makeAddr("alice");
        scheduler = new EmissionScheduler(mintDistributor);
    }

    function test_Constructor() public view {
        assertEq(scheduler.MINT_DISTRIBUTOR(), mintDistributor);
        assertEq(scheduler.EMISSION_START_TIME(), block.timestamp);
        assertEq(scheduler.totalEmitted(), 0);
        // Emission schedule: Year 1 = 3.6M, Total Cap = 14.4M (80% of 18M max supply)
        assertEq(scheduler.YEAR_1_EMISSION(), 3_600_000e18);
        assertEq(scheduler.EMISSION_CAP(), 14_400_000e18);
    }

    function test_Constructor_RevertsOnZeroMintDistributor() public {
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        new EmissionScheduler(address(0));
    }

    function test_GetYearEmission_Year0() public view {
        // Year 1 (index 0): 3,600,000 DMD
        assertEq(scheduler.getYearEmission(0), 3_600_000e18);
    }

    function test_GetYearEmission_Year1() public view {
        // Year 2 (index 1): 2,700,000 DMD (75% of 3.6M)
        assertEq(scheduler.getYearEmission(1), 2_700_000e18);
    }

    function test_GetYearEmission_Year2() public view {
        // Year 3 (index 2): 2,025,000 DMD
        assertEq(scheduler.getYearEmission(2), 2_025_000e18);
    }

    function test_GetYearEmission_Year3() public view {
        // Year 4 (index 3): 1,518,750 DMD
        assertEq(scheduler.getYearEmission(3), 1_518_750e18);
    }

    function test_GetYearEmission_Year4() public view {
        // Year 5 (index 4): 1,139,062.5 DMD
        assertEq(scheduler.getYearEmission(4), 1_139_062500000000000000000);
    }

    function test_GetYearEmission_Year5() public view {
        // Year 6 (index 5): 854,296.875 DMD
        assertEq(scheduler.getYearEmission(5), 854_296875000000000000000);
    }

    function test_GetYearEmission_Year6() public view {
        // Year 7 (index 6): 640,722.65625 DMD
        assertEq(scheduler.getYearEmission(6), 640_722656250000000000000);
    }

    function test_ClaimEmission_RevertsOnUnauthorized() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert(EmissionScheduler.Unauthorized.selector);
        scheduler.claimEmission();
    }

    function test_ClaimEmission_OneDay() public {
        vm.warp(block.timestamp + 1 days);
        // Daily emission = 3.6M / 365 days
        uint256 expectedEmission = (3_600_000e18 * 1 days) / uint256(365 days);
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();
        assertApproxEqAbs(claimed, expectedEmission, 1e18);
    }

    function test_ClaimEmission_FullYear() public {
        vm.warp(block.timestamp + 365 days);
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();
        assertApproxEqAbs(claimed, 3_600_000e18, 1e18);
        assertEq(scheduler.getCurrentYear(), 1);
    }

    function test_ClaimEmission_TwoYears() public {
        // Year 1: 3.6M + Year 2: 2.7M = 6.3M
        vm.warp(block.timestamp + (2 * 365 days));
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();
        assertApproxEqAbs(claimed, 6_300_000e18, 1e18);
    }

    function test_ClaimEmission_EnforcesCap() public {
        vm.warp(block.timestamp + (50 * 365 days));
        vm.prank(mintDistributor);
        uint256 claimed = scheduler.claimEmission();
        assertLe(claimed, scheduler.EMISSION_CAP());
    }

    function test_ClaimableNow_AtStart() public view {
        assertEq(scheduler.claimableNow(), 0);
    }

    function test_GetCurrentYear() public {
        assertEq(scheduler.getCurrentYear(), 0);
        vm.warp(block.timestamp + 365 days);
        assertEq(scheduler.getCurrentYear(), 1);
    }

    function test_CapReached() public {
        assertFalse(scheduler.capReached());
        // With Year 1 = 3.6M and 25% decay, geometric series sum converges to ~14.4M
        // (geometric series: 3.6M / 0.25 = 14.4M)
        // After 100 years, we should be very close to the cap
        vm.warp(block.timestamp + (100 * 365 days));
        vm.prank(mintDistributor);
        scheduler.claimEmission();

        // Verify we're within 1 DMD of the cap (essentially all emissions distributed)
        uint256 remaining = scheduler.EMISSION_CAP() - scheduler.totalEmitted();
        assertLt(remaining, 1e18, "Should be within 1 DMD of cap after 100 years");
        assertLt(scheduler.claimableNow(), 1e18, "Claimable should be dust after 100 years");
    }

    function test_EmissionSchedule_MatchesSpec() public view {
        // Verify the exact emission schedule from spec
        assertEq(scheduler.getYearEmission(0), 3_600_000e18, "Year 1 should be 3.6M");
        assertEq(scheduler.getYearEmission(1), 2_700_000e18, "Year 2 should be 2.7M");
        assertEq(scheduler.getYearEmission(2), 2_025_000e18, "Year 3 should be 2.025M");
        assertEq(scheduler.getYearEmission(3), 1_518_750e18, "Year 4 should be 1,518,750");
    }

    function test_DecayRate() public view {
        // Verify 25% decay (multiply by 0.75 each year)
        for (uint256 i = 0; i < 10; i++) {
            uint256 thisYear = scheduler.getYearEmission(i);
            uint256 nextYear = scheduler.getYearEmission(i + 1);
            // nextYear should be exactly 75% of thisYear
            assertEq(nextYear, (thisYear * 75) / 100, "Decay should be exactly 25%");
        }
    }
}
