// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/MintDistributor.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract MockBTCReserveVault {
    mapping(address => uint256) public totalWeightOf;
    uint256 public totalSystemWeight;

    function setUserWeight(address user, uint256 weight) external {
        totalWeightOf[user] = weight;
    }

    function setSystemWeight(uint256 weight) external {
        totalSystemWeight = weight;
    }
}

contract MockEmissionScheduler {
    uint256 public nextClaimAmount;
    uint256 public claimableAmount;

    function setNextClaimAmount(uint256 amount) external {
        nextClaimAmount = amount;
    }

    function setClaimableAmount(uint256 amount) external {
        claimableAmount = amount;
    }

    function claimEmission() external returns (uint256) {
        uint256 amount = nextClaimAmount;
        nextClaimAmount = 0;
        return amount;
    }

    function claimableNow() external view returns (uint256) {
        return claimableAmount;
    }
}

contract MintDistributorTest is Test {
    MintDistributor public distributor;
    MockDMDToken public dmdToken;
    MockBTCReserveVault public vault;
    MockEmissionScheduler public scheduler;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    event DistributionStarted(uint256 startTime);
    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        dmdToken = new MockDMDToken();
        vault = new MockBTCReserveVault();
        scheduler = new MockEmissionScheduler();

        vm.prank(owner);
        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(distributor.owner(), owner);
        assertEq(address(distributor.dmdToken()), address(dmdToken));
        assertEq(address(distributor.vault()), address(vault));
        assertEq(address(distributor.scheduler()), address(scheduler));
        assertEq(distributor.EPOCH_DURATION(), 7 days);
        assertEq(distributor.distributionStartTime(), 0);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        new MintDistributor(
            address(0),
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        new MintDistributor(
            owner,
            IDMDToken(address(0)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor_RevertsOnZeroVault() public {
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(0)),
            IEmissionScheduler(address(scheduler))
        );
    }

    function test_Constructor_RevertsOnZeroScheduler() public {
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(0))
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartDistribution_Success() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit DistributionStarted(startTime);
        distributor.startDistribution();

        assertEq(distributor.distributionStartTime(), startTime);
        assertEq(distributor.getCurrentEpoch(), 0);
    }

    function test_StartDistribution_RevertsOnUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        distributor.startDistribution();
    }

    function test_StartDistribution_RevertsOnAlreadyStarted() public {
        vm.prank(owner);
        distributor.startDistribution();

        vm.prank(owner);
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        distributor.startDistribution();
    }

    /*//////////////////////////////////////////////////////////////
                          EPOCH CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentEpoch_BeforeStart() public {
        assertEq(distributor.getCurrentEpoch(), 0);
    }

    function test_GetCurrentEpoch_EpochZero() public {
        vm.prank(owner);
        distributor.startDistribution();

        assertEq(distributor.getCurrentEpoch(), 0);

        vm.warp(block.timestamp + 6 days);
        assertEq(distributor.getCurrentEpoch(), 0);
    }

    function test_GetCurrentEpoch_EpochOne() public {
        vm.prank(owner);
        distributor.startDistribution();

        vm.warp(block.timestamp + 7 days);
        assertEq(distributor.getCurrentEpoch(), 1);

        vm.warp(block.timestamp + 6 days);
        assertEq(distributor.getCurrentEpoch(), 1);
    }

    function test_GetCurrentEpoch_MultipleEpochs() public {
        vm.prank(owner);
        distributor.startDistribution();

        vm.warp(block.timestamp + (7 days * 5));
        assertEq(distributor.getCurrentEpoch(), 5);
    }

    /*//////////////////////////////////////////////////////////////
                          EPOCH FINALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeEpoch_RevertsBeforeStart() public {
        vm.expectRevert(MintDistributor.Unauthorized.selector);
        distributor.finalizeEpoch();
    }

    function test_FinalizeEpoch_RevertsInEpochZero() public {
        vm.prank(owner);
        distributor.startDistribution();

        vm.expectRevert(MintDistributor.EpochNotFinalized.selector);
        distributor.finalizeEpoch();
    }

    function test_FinalizeEpoch_Success() public {
        vm.prank(owner);
        distributor.startDistribution();

        // Set up system weight
        vault.setSystemWeight(1000e18);

        // Set emission amount
        scheduler.setNextClaimAmount(100e18);

        // Move to epoch 1
        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, false, false, true);
        emit EpochFinalized(0, 100e18, 1000e18);
        distributor.finalizeEpoch();

        (uint256 totalEmission, uint256 snapshotWeight, bool finalized) = 
            distributor.getEpochData(0);

        assertEq(totalEmission, 100e18);
        assertEq(snapshotWeight, 1000e18);
        assertTrue(finalized);
    }

    function test_FinalizeEpoch_RevertsOnAlreadyFinalized() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(100e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.expectRevert(MintDistributor.EpochNotFinalized.selector);
        distributor.finalizeEpoch();
    }

    function test_FinalizeEpoch_RevertsOnZeroEmission() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(0);

        vm.warp(block.timestamp + 7 days);

        vm.expectRevert(MintDistributor.NoEmissionsAvailable.selector);
        distributor.finalizeEpoch();
    }

    function test_FinalizeEpoch_PermissionlessCall() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(100e18);

        vm.warp(block.timestamp + 7 days);

        // Anyone can finalize
        vm.prank(alice);
        distributor.finalizeEpoch();

        (, , bool finalized) = distributor.getEpochData(0);
        assertTrue(finalized);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Claim_Success() public {
        vm.prank(owner);
        distributor.startDistribution();

        // Setup: Alice has 300e18 weight, total system weight 1000e18
        vault.setUserWeight(alice, 300e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Alice should get 300/1000 * 1000 = 300 DMD
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, 0, 300e18);
        distributor.claim(0);

        assertEq(dmdToken.balanceOf(alice), 300e18);
        assertTrue(distributor.claimed(0, alice));
    }

    function test_Claim_ProportionalDistribution() public {
        vm.prank(owner);
        distributor.startDistribution();

        // Alice: 500, Bob: 300, Charlie: 200, Total: 1000
        vault.setUserWeight(alice, 500e18);
        vault.setUserWeight(bob, 300e18);
        vault.setUserWeight(charlie, 200e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);
        assertEq(dmdToken.balanceOf(alice), 500e18);

        vm.prank(bob);
        distributor.claim(0);
        assertEq(dmdToken.balanceOf(bob), 300e18);

        vm.prank(charlie);
        distributor.claim(0);
        assertEq(dmdToken.balanceOf(charlie), 200e18);
    }

    function test_Claim_RevertsOnNotFinalized() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(MintDistributor.EpochNotFinalized.selector);
        distributor.claim(0);
    }

    function test_Claim_RevertsOnAlreadyClaimed() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 300e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.startPrank(alice);
        distributor.claim(0);

        vm.expectRevert(MintDistributor.AlreadyClaimed.selector);
        distributor.claim(0);
        vm.stopPrank();
    }

    function test_Claim_RevertsOnNoWeight() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 0);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        vm.expectRevert(MintDistributor.NoWeight.selector);
        distributor.claim(0);
    }

    /*//////////////////////////////////////////////////////////////
                          BATCH CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimMultiple_Success() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 500e18);
        vault.setSystemWeight(1000e18);

        // Finalize 3 epochs
        for (uint256 i = 0; i < 3; i++) {
            scheduler.setNextClaimAmount(1000e18);
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
        }

        uint256[] memory epochIds = new uint256[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.prank(alice);
        distributor.claimMultiple(epochIds);

        // Alice gets 500/1000 * 1000 = 500 per epoch
        assertEq(dmdToken.balanceOf(alice), 1500e18);
        assertTrue(distributor.claimed(0, alice));
        assertTrue(distributor.claimed(1, alice));
        assertTrue(distributor.claimed(2, alice));
    }

    function test_ClaimMultiple_SkipsAlreadyClaimed() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 500e18);
        vault.setSystemWeight(1000e18);

        // Finalize 2 epochs
        for (uint256 i = 0; i < 2; i++) {
            scheduler.setNextClaimAmount(1000e18);
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
        }

        // Claim epoch 0 individually
        vm.prank(alice);
        distributor.claim(0);

        uint256[] memory epochIds = new uint256[](2);
        epochIds[0] = 0;
        epochIds[1] = 1;

        vm.prank(alice);
        distributor.claimMultiple(epochIds);

        // Should have 500 (from first claim) + 500 (epoch 1) = 1000
        assertEq(dmdToken.balanceOf(alice), 1000e18);
    }

    function test_ClaimMultiple_SkipsUnfinalized() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 500e18);
        vault.setSystemWeight(1000e18);

        // Only finalize epoch 0
        scheduler.setNextClaimAmount(1000e18);
        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        uint256[] memory epochIds = new uint256[](2);
        epochIds[0] = 0;
        epochIds[1] = 1; // Not finalized

        vm.prank(alice);
        distributor.claimMultiple(epochIds);

        // Should only get epoch 0
        assertEq(dmdToken.balanceOf(alice), 500e18);
        assertTrue(distributor.claimed(0, alice));
        assertFalse(distributor.claimed(1, alice));
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetClaimableAmount() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 300e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        uint256 claimable = distributor.getClaimableAmount(alice, 0);
        assertEq(claimable, 300e18);
    }

    function test_GetClaimableAmount_ZeroAfterClaim() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 300e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        uint256 claimable = distributor.getClaimableAmount(alice, 0);
        assertEq(claimable, 0);
    }

    function test_HasClaimed() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 300e18);
        vault.setSystemWeight(1000e18);
        scheduler.setNextClaimAmount(1000e18);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        assertFalse(distributor.hasClaimed(alice, 0));

        vm.prank(alice);
        distributor.claim(0);

        assertTrue(distributor.hasClaimed(alice, 0));
    }

    function test_GetTotalClaimable() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 500e18);
        vault.setSystemWeight(1000e18);

        // Finalize 3 epochs
        for (uint256 i = 0; i < 3; i++) {
            scheduler.setNextClaimAmount(1000e18);
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
        }

        uint256[] memory epochIds = new uint256[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        uint256 totalClaimable = distributor.getTotalClaimable(alice, epochIds);
        assertEq(totalClaimable, 1500e18);
    }

    function test_GetTotalClaimable_ExcludesClaimed() public {
        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, 500e18);
        vault.setSystemWeight(1000e18);

        // Finalize 2 epochs
        for (uint256 i = 0; i < 2; i++) {
            scheduler.setNextClaimAmount(1000e18);
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
        }

        // Claim epoch 0
        vm.prank(alice);
        distributor.claim(0);

        uint256[] memory epochIds = new uint256[](2);
        epochIds[0] = 0;
        epochIds[1] = 1;

        uint256 totalClaimable = distributor.getTotalClaimable(alice, epochIds);
        assertEq(totalClaimable, 500e18); // Only epoch 1
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Claim(uint256 userWeight, uint256 systemWeight, uint256 emission) public {
        userWeight = bound(userWeight, 1, 1e30);
        systemWeight = bound(systemWeight, userWeight, 1e30);
        emission = bound(emission, 1, 1e30);

        vm.prank(owner);
        distributor.startDistribution();

        vault.setUserWeight(alice, userWeight);
        vault.setSystemWeight(systemWeight);
        scheduler.setNextClaimAmount(emission);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        uint256 expectedShare = (emission * userWeight) / systemWeight;
        assertEq(dmdToken.balanceOf(alice), expectedShare);
    }

    function testFuzz_GetCurrentEpoch(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days);

        vm.prank(owner);
        distributor.startDistribution();

        vm.warp(block.timestamp + timeElapsed);

        uint256 currentEpoch = distributor.getCurrentEpoch();
        uint256 expectedEpoch = timeElapsed / 7 days;

        assertEq(currentEpoch, expectedEpoch);
    }
}