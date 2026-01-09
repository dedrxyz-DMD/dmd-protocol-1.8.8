// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {MintDistributor, IDMDToken, IBTCReserveVault, IEmissionScheduler} from "../src/MintDistributor.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract MockBTCReserveVault {
    mapping(address => uint256) public vestedWeight;
    uint256 public totalVestedWeightVal;
    mapping(address => uint256[]) public activePositionsList;
    mapping(address => mapping(uint256 => uint256)) public posVestedWeight;
    mapping(address => uint256) public activePositionCountVal;

    function setVestedWeight(address user, uint256 weight) external {
        vestedWeight[user] = weight;
    }

    function setTotalVestedWeight(uint256 weight) external {
        totalVestedWeightVal = weight;
    }

    function setActivePositionCount(address user, uint256 count) external {
        activePositionCountVal[user] = count;
    }

    function setActivePositions(address user, uint256[] memory positions) external {
        activePositionsList[user] = positions;
    }

    function setPositionVestedWeight(address user, uint256 posId, uint256 weight) external {
        posVestedWeight[user][posId] = weight;
    }

    function getVestedWeight(address user) external view returns (uint256) {
        return vestedWeight[user];
    }

    function getTotalVestedWeight() external view returns (uint256) {
        return totalVestedWeightVal;
    }

    function getActivePositions(address user) external view returns (uint256[] memory) {
        return activePositionsList[user];
    }

    function getActivePositionCount(address user) external view returns (uint256) {
        return activePositionCountVal[user];
    }

    function getPositionVestedWeight(address user, uint256 posId) external view returns (uint256) {
        return posVestedWeight[user][posId];
    }

    function getTotalUsers() external pure returns (uint256) {
        return 0;
    }
}

contract MockEmissionScheduler {
    uint256 public nextClaimAmount;

    function setNextClaimAmount(uint256 amount) external {
        nextClaimAmount = amount;
    }

    function claimEmission() external returns (uint256) {
        uint256 amount = nextClaimAmount;
        nextClaimAmount = 0;
        return amount;
    }
}

contract MintDistributorTest is Test {
    MintDistributor public distributor;
    MockDMDToken public dmdToken;
    MockBTCReserveVault public vault;
    MockEmissionScheduler public scheduler;

    address public alice;
    address public bob;

    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight, uint256 finalizationTime);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);
    event WeightSnapshotted(uint256 indexed epochId, address indexed user, uint256 weight);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        dmdToken = new MockDMDToken();
        vault = new MockBTCReserveVault();
        scheduler = new MockEmissionScheduler();

        distributor = new MintDistributor(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor() public view {
        assertEq(address(distributor.DMD_TOKEN()), address(dmdToken));
        assertEq(address(distributor.VAULT()), address(vault));
        assertEq(address(distributor.SCHEDULER()), address(scheduler));
        assertEq(distributor.EPOCH_DURATION(), 7 days);
        assertEq(distributor.DISTRIBUTION_START_TIME(), block.timestamp);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(MintDistributor.InvalidAddress.selector);
        new MintDistributor(
            IDMDToken(address(0)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor_RevertsOnZeroVault() public {
        vm.expectRevert(MintDistributor.InvalidAddress.selector);
        new MintDistributor(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(0)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor_RevertsOnZeroScheduler() public {
        vm.expectRevert(MintDistributor.InvalidAddress.selector);
        new MintDistributor(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(0))
        );
    }

    function test_GetCurrentEpoch_EpochZero() public view {
        assertEq(distributor.getCurrentEpoch(), 0);
    }

    function test_GetCurrentEpoch_StillZeroBeforeSevenDays() public {
        vm.warp(block.timestamp + 6 days);
        assertEq(distributor.getCurrentEpoch(), 0);
    }

    function test_GetCurrentEpoch_EpochOne() public {
        vm.warp(block.timestamp + 7 days);
        assertEq(distributor.getCurrentEpoch(), 1);
    }

    function test_FinalizeEpoch_RevertsInEpochZero() public {
        vm.expectRevert(MintDistributor.InvalidEpoch.selector);
        distributor.finalizeEpoch();
    }

    function test_FinalizeEpoch_Success() public {
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(100e18);
        vm.warp(block.timestamp + 7 days);

        distributor.finalizeEpoch();

        (uint256 totalEmission, uint256 snapshotWeight, bool finalized) =
            distributor.getEpochData(0);

        assertEq(totalEmission, 100e18);
        assertEq(snapshotWeight, 1000e18);
        assertTrue(finalized);
    }

    function test_FinalizeEpoch_RevertsOnZeroEmission() public {
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(0);
        vm.warp(block.timestamp + 7 days);

        vm.expectRevert(MintDistributor.NoEmissionsAvailable.selector);
        distributor.finalizeEpoch();
    }

    function test_Claim_Success() public {
        // Setup: Alice has position before finalization
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        // Setup positions for snapshot
        uint256[] memory positions = new uint256[](1);
        positions[0] = 0;
        vault.setActivePositions(alice, positions);
        vault.setPositionVestedWeight(alice, 0, 300e18);
        vault.setVestedWeight(alice, 300e18);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        // Move to epoch 1 and finalize epoch 0
        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Alice snapshots and claims
        vm.startPrank(alice);
        distributor.snapshotMyWeight(0);

        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, 0, 300e18);
        distributor.claim(0);
        vm.stopPrank();

        assertEq(dmdToken.balanceOf(alice), 300e18);
        assertTrue(distributor.hasClaimed(alice, 0));
    }

    function test_Claim_RevertsWithoutSnapshot() public {
        // Setup: Alice has position before finalization
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        vault.setVestedWeight(alice, 300e18);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Alice tries to claim without snapshot
        vm.prank(alice);
        vm.expectRevert(MintDistributor.UserNotEligible.selector);
        distributor.claim(0);
    }

    function test_Claim_RevertsOnDoubleClaim() public {
        // Setup: Alice has position before finalization
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        uint256[] memory positions = new uint256[](1);
        positions[0] = 0;
        vault.setActivePositions(alice, positions);
        vault.setPositionVestedWeight(alice, 0, 300e18);
        vault.setVestedWeight(alice, 300e18);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.startPrank(alice);
        distributor.snapshotMyWeight(0);
        distributor.claim(0);

        // Second claim should revert with NoWeight (returns 0 internally, then reverts)
        vm.expectRevert(MintDistributor.NoWeight.selector);
        distributor.claim(0);
        vm.stopPrank();
    }

    function test_Claim_RevertsOnNoWeight() public {
        // Setup: Alice registered but has 0 weight
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        uint256[] memory positions = new uint256[](1);
        positions[0] = 0;
        vault.setActivePositions(alice, positions);
        vault.setPositionVestedWeight(alice, 0, 0);
        vault.setVestedWeight(alice, 0);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Snapshot returns early if weight is 0
        vm.startPrank(alice);
        distributor.snapshotMyWeight(0); // This will not actually snapshot (weight = 0)

        vm.expectRevert(MintDistributor.UserNotEligible.selector);
        distributor.claim(0);
        vm.stopPrank();
    }

    function test_Snapshot_RevertsForLateJoiner() public {
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Bob registers AFTER epoch finalization
        vault.setActivePositionCount(bob, 1);
        distributor.registerUserFirstLock(bob);

        vault.setVestedWeight(bob, 500e18);

        // Bob tries to snapshot - should fail (late joiner)
        vm.prank(bob);
        vm.expectRevert(MintDistributor.UserNotEligible.selector);
        distributor.snapshotMyWeight(0);
    }

    function test_Snapshot_RevertsForNonUser() public {
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Bob has no position
        vm.prank(bob);
        vm.expectRevert(MintDistributor.UserNotEligible.selector);
        distributor.snapshotMyWeight(0);
    }

    function test_SnapshotUserWeight_RevertsUnauthorized() public {
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        vault.setVestedWeight(alice, 300e18);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Bob tries to snapshot Alice's weight - should fail (griefing prevention)
        vm.prank(bob);
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        distributor.snapshotUserWeight(0, alice);
    }

    function test_GetClaimableAmount() public {
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        uint256[] memory positions = new uint256[](1);
        positions[0] = 0;
        vault.setActivePositions(alice, positions);
        vault.setPositionVestedWeight(alice, 0, 300e18);
        vault.setVestedWeight(alice, 300e18);
        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Before snapshot, claimable should be 0
        uint256 claimableBefore = distributor.getClaimableAmount(alice, 0);
        assertEq(claimableBefore, 0);

        // After snapshot
        vm.prank(alice);
        distributor.snapshotMyWeight(0);

        uint256 claimableAfter = distributor.getClaimableAmount(alice, 0);
        assertEq(claimableAfter, 300e18);
    }

    function test_IsEligibleForEpoch() public {
        vault.setActivePositionCount(alice, 1);
        distributor.registerUserFirstLock(alice);

        vault.setTotalVestedWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        assertTrue(distributor.isEligibleForEpoch(alice, 0));
        assertFalse(distributor.isEligibleForEpoch(bob, 0));
    }

    function testFuzz_GetCurrentEpoch(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days);
        vm.warp(block.timestamp + timeElapsed);
        uint256 currentEpoch = distributor.getCurrentEpoch();
        uint256 expectedEpoch = timeElapsed / 7 days;
        assertEq(currentEpoch, expectedEpoch);
    }
}
