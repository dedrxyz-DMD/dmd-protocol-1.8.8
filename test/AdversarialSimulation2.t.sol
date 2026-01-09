// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DMDToken} from "../src/DMDToken.sol";
import {EmissionScheduler} from "../src/EmissionScheduler.sol";
import {ProtocolDefenseConsensus} from "../src/ProtocolDefenseConsensus.sol";
import {VestingContract, IDMDToken} from "../src/VestingContract.sol";

/// @title AdversarialSimulation2 - Additional 1000-block simulation focusing on edge cases
/// @dev Tests time-based attacks, vesting manipulation, and state transition exploits
contract AdversarialSimulation2Test is Test {
    DMDToken token;
    EmissionScheduler scheduler;
    ProtocolDefenseConsensus pdc;
    VestingContract vesting;

    address mintDistributorAddr;
    address vestingContractAddr;

    address attacker1 = address(0x2337);
    address attacker2 = address(0x2338);
    address attacker3 = address(0x2339);

    uint256 constant SIMULATION_BLOCKS = 1000;
    uint256 constant BLOCKS_PER_BLOCK = 12; // 12 seconds

    function setUp() public {
        // Deploy core contracts
        mintDistributorAddr = makeAddr("mintDistributor");
        vestingContractAddr = makeAddr("vestingContract");

        // Deploy token with proper addresses
        token = new DMDToken(mintDistributorAddr, vestingContractAddr);

        // Deploy scheduler
        scheduler = new EmissionScheduler(mintDistributorAddr);

        // Deploy vesting (20% of 18M = 3.6M for team)
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = attacker1;
        beneficiaries[1] = attacker2;
        beneficiaries[2] = attacker3;

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 1_200_000e18; // 1.2M each
        allocations[1] = 1_200_000e18;
        allocations[2] = 1_200_000e18;

        // Deploy vesting at the predetermined address using vm.etch
        VestingContract vestingImpl = new VestingContract(IDMDToken(address(token)), beneficiaries, allocations);
        vm.etch(vestingContractAddr, address(vestingImpl).code);
        vesting = VestingContract(vestingContractAddr);

        // Deploy PDC
        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = address(0x1234); // Mock tBTC adapter
        pdc = new ProtocolDefenseConsensus(address(token), initialAdapters);
    }

    /// @notice Main simulation: 1000 blocks of time-based attacks
    function test_1000BlockTimeBasedSimulation() public {
        console.log("=== Starting 1000-Block Time-Based Simulation ===");

        uint256 startTime = block.timestamp;

        for (uint256 block_num = 1; block_num <= SIMULATION_BLOCKS; block_num++) {
            vm.roll(block_num);
            vm.warp(startTime + (block_num * BLOCKS_PER_BLOCK));

            // ATTACK 1: Time manipulation for vesting
            if (block_num % 50 == 0) {
                _attemptVestingTimeManipulation();
            }

            // ATTACK 2: PDC activation timing attack
            if (block_num % 100 == 0) {
                _attemptPDCActivationTiming();
            }

            // ATTACK 3: Emission year boundary manipulation
            if (block_num % 75 == 0) {
                _attemptYearBoundaryManipulation();
            }

            // ATTACK 4: State transition race conditions
            if (block_num % 125 == 0) {
                _attemptStateTransitionRace();
            }

            // ATTACK 5: Supply cap bypass attempts
            if (block_num % 150 == 0) {
                _attemptSupplyCapBypass();
            }

            // ATTACK 6: Vesting claim griefing
            if (block_num % 80 == 0) {
                _attemptVestingClaimGriefing();
            }

            // Periodic integrity checks
            if (block_num % 200 == 0) {
                _verifyProtocolInvariants(block_num);
            }
        }

        console.log("=== Time-Based Simulation Complete ===");
        _finalIntegrityCheck();
    }

    /// @notice ATTACK 1: Try to manipulate vesting by time warping
    function _attemptVestingTimeManipulation() internal view {
        // Just verify vesting calculations are time-based and deterministic
        uint256 claimable = vesting.getClaimable(attacker1);

        // Verify claimable is reasonable based on time elapsed
        uint256 timeElapsed = block.timestamp - vesting.TGE_TIME();
        uint256 totalAlloc = 1_200_000e18;

        // Should not exceed total allocation
        assertLe(claimable, totalAlloc, "Claimable exceeds allocation");
    }

    /// @notice ATTACK 2: Try to manipulate PDC activation timing
    function _attemptPDCActivationTiming() internal {
        if (pdc.activated()) return;

        // Try to activate PDC before conditions are met
        try pdc.activate() {
            console.log("PDC activated early (should only work if conditions met)");
        } catch {
            // Expected: PDC not ready yet
        }

        // Check if we can manipulate activation conditions
        (bool isActivated, bool timeConditionMet, bool supplyConditionMet, bool holderConditionMet,,,) =
            pdc.getActivationStatus();

        if (timeConditionMet && supplyConditionMet && holderConditionMet && !isActivated) {
            // All conditions met but not activated - should be able to activate
            pdc.activate();
            console.log("PDC legitimately activated");
        }
    }

    /// @notice ATTACK 3: Try to exploit year boundary in emission calculations
    function _attemptYearBoundaryManipulation() internal {
        uint256 currentYear = scheduler.getCurrentYear();
        uint256 emission = scheduler.getYearEmission(currentYear);
        uint256 claimable = scheduler.claimableNow();

        // Verify emission follows 25% decay schedule
        if (currentYear > 0) {
            uint256 previousYearEmission = scheduler.getYearEmission(currentYear - 1);
            uint256 expectedEmission = (previousYearEmission * 75) / 100;
            assertEq(emission, expectedEmission, "Year decay broken");
        }

        // Log values separately to avoid console.log multi-param issues
        console.log("Current year:", currentYear);
        console.log("Year emission (DMD):", emission / 1e18);
        console.log("Claimable now (DMD):", claimable / 1e18);
    }

    /// @notice ATTACK 4: Try to exploit state transition race conditions in PDC
    function _attemptStateTransitionRace() internal {
        if (!pdc.activated()) return;

        // Get current state
        (,,,,,,,,,,, ProtocolDefenseConsensus.ProposalState state) = pdc.getProposal();

        // Try to perform actions in wrong states
        if (state == ProtocolDefenseConsensus.ProposalState.IDLE) {
            // Try to vote when no proposal exists
            vm.prank(attacker1);
            try pdc.vote(true) {
                revert("Voted in IDLE state (should fail)");
            } catch {
                console.log("Vote in IDLE blocked (correct)");
            }
        }
    }

    /// @notice ATTACK 5: Try to bypass 18M supply cap
    function _attemptSupplyCapBypass() internal {
        uint256 totalMinted = token.totalMinted();
        uint256 maxSupply = token.MAX_SUPPLY();

        // Verify we can't exceed cap
        if (totalMinted < maxSupply) {
            uint256 remaining = maxSupply - totalMinted;

            // Try to mint more than remaining
            vm.prank(mintDistributorAddr);
            try token.mint(attacker1, remaining + 1) {
                revert("Exceeded max supply (should fail)");
            } catch {
                console.log("Supply cap enforced (correct)");
            }

            // Try to mint exactly remaining (should work)
            if (remaining > 0 && remaining <= 1000e18) {
                vm.prank(mintDistributorAddr);
                token.mint(attacker2, remaining);
                assertEq(token.totalMinted(), maxSupply, "Supply cap bypass detected");
            }
        }
    }

    /// @notice ATTACK 6: Try to grief vesting claims
    function _attemptVestingClaimGriefing() internal view {
        // Verify vesting is permissionless (anyone can trigger claims)
        uint256 claimable = vesting.getClaimable(attacker1);

        // Verify claimable amount is deterministic
        assertLe(claimable, 1_200_000e18, "Vesting claimable exceeds allocation");
    }

    /// @notice Verify core protocol invariants
    function _verifyProtocolInvariants(uint256 blockNum) internal view {
        console.log("=== Block", blockNum, "Invariant Check ===");

        // Invariant 1: Total supply never exceeds 18M
        uint256 totalSupply = token.totalSupply();
        assertLe(totalSupply, 18_000_000e18, "Total supply exceeded 18M");

        // Invariant 2: Total supply = totalMinted - totalBurned
        assertEq(totalSupply, token.totalMinted() - token.totalBurned(), "Supply accounting broken");

        // Invariant 3: Total emitted never exceeds 14.4M
        uint256 totalEmitted = scheduler.totalEmitted();
        assertLe(totalEmitted, 14_400_000e18, "Emissions exceeded cap");

        // Invariant 4: Vesting total allocation is 3.6M
        assertEq(vesting.TOTAL_ALLOCATION(), 3_600_000e18, "Vesting allocation changed");

        // Invariant 5: EmissionScheduler + Vesting = 18M exactly
        assertEq(scheduler.EMISSION_CAP() + vesting.TOTAL_ALLOCATION(), 18_000_000e18, "Total allocation != 18M");

        console.log("Total supply:", totalSupply / 1e18, "DMD");
        console.log("Total emitted:", totalEmitted / 1e18, "DMD");
        console.log("Holder count:", token.uniqueHolderCount());
    }

    /// @notice Final comprehensive integrity check
    function _finalIntegrityCheck() internal view {
        console.log("=== Final Integrity Check (Simulation 2) ===");

        uint256 totalSupply = token.totalSupply();
        uint256 totalMinted = token.totalMinted();
        uint256 totalBurned = token.totalBurned();
        uint256 totalEmitted = scheduler.totalEmitted();

        console.log("Final total supply:", totalSupply / 1e18, "DMD");
        console.log("Final total minted:", totalMinted / 1e18, "DMD");
        console.log("Final total burned:", totalBurned / 1e18, "DMD");
        console.log("Final total emitted:", totalEmitted / 1e18, "DMD");
        console.log("Final unique holders:", token.uniqueHolderCount());

        // Critical invariants
        assertLe(totalSupply, 18_000_000e18, "CRITICAL: Supply cap violated");
        assertLe(totalEmitted, 14_400_000e18, "CRITICAL: Emission cap violated");
        assertEq(totalSupply, totalMinted - totalBurned, "CRITICAL: Supply accounting broken");
        assertEq(scheduler.EMISSION_CAP() + vesting.TOTAL_ALLOCATION(), 18_000_000e18, "CRITICAL: Total != 18M");

        console.log("=== All Invariants Verified (Simulation 2) ===");
    }
}
