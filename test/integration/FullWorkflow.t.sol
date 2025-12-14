// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/DMDToken.sol";
import "../src/BTCReserveVault.sol";
import "../src/EmissionScheduler.sol";
import "../src/MintDistributor.sol";
import "../src/RedemptionEngine.sol";
import "../src/VestingContract.sol";

contract MockWBTC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "INSUFFICIENT_BALANCE");
        require(allowance[from][msg.sender] >= amount, "INSUFFICIENT_ALLOWANCE");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract FullWorkflowTest is Test {
    // Core contracts
    DMDToken public dmdToken;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    RedemptionEngine public redemptionEngine;
    VestingContract public vesting;
    
    // Mock
    MockWBTC public wbtc;

    // Actors
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public foundation;

    uint256 constant WBTC_AMOUNT = 1e8; // 1 WBTC

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        foundation = makeAddr("foundation");

        // Deploy mock WBTC
        wbtc = new MockWBTC();

        // Deploy core contracts in dependency order
        vm.startPrank(owner);

        // 1. DMDToken (needs MintDistributor address - deploy after distributor)
        // Deploy placeholder for now, will set correct address pattern

        // 2. BTCReserveVault (needs redemptionEngine address)
        // Deploy with placeholder

        // 3. EmissionScheduler
        scheduler = new EmissionScheduler(owner, address(1)); // Placeholder for distributor

        // 4. Deploy DMDToken with placeholder
        dmdToken = new DMDToken(address(1)); // Placeholder

        // 5. Deploy vault with placeholder
        vault = new BTCReserveVault(address(wbtc), address(1)); // Placeholder

        vm.stopPrank();

        // Now deploy actual contracts with correct addresses
        vm.startPrank(owner);
        
        // Redeploy with correct cross-references
        DMDToken newDMDToken = new DMDToken(address(0)); // Will set after distributor
        EmissionScheduler newScheduler = new EmissionScheduler(owner, address(0));
        
        // Deploy MintDistributor (needs all three)
        distributor = new MintDistributor(
            owner,
            IDMDToken(address(newDMDToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(newScheduler))
        );

        // Redeploy DMDToken with correct MintDistributor
        dmdToken = new DMDToken(address(distributor));

        // Redeploy EmissionScheduler with correct MintDistributor
        scheduler = new EmissionScheduler(owner, address(distributor));

        // Deploy RedemptionEngine
        redemptionEngine = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );

        // Redeploy BTCReserveVault with correct RedemptionEngine
        vault = new BTCReserveVault(address(wbtc), address(redemptionEngine));

        // Redeploy MintDistributor with correct vault
        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );

        // Final: Redeploy DMDToken with correct distributor
        dmdToken = new DMDToken(address(distributor));

        // Deploy VestingContract
        vesting = new VestingContract(owner, IDMDToken(address(dmdToken)));

        vm.stopPrank();

        // Fund test users with WBTC
        wbtc.mint(alice, 10 * WBTC_AMOUNT);
        wbtc.mint(bob, 10 * WBTC_AMOUNT);
        wbtc.mint(charlie, 10 * WBTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          HAPPY PATH WORKFLOW
    //////////////////////////////////////////////////////////////*/

    function test_HappyPath_SingleUser() public {
        // 1. Start emissions and distribution
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // 2. Alice locks WBTC for 12 months
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        uint256 aliceWeight = vault.calculateWeight(WBTC_AMOUNT, 12);
        assertEq(vault.totalWeightOf(alice), aliceWeight);

        // 3. Wait for epoch to complete (7 days)
        vm.warp(block.timestamp + 7 days);

        // 4. Finalize epoch 0
        distributor.finalizeEpoch();

        (uint256 totalEmission, uint256 snapshotWeight, bool finalized) = 
            distributor.getEpochData(0);
        
        assertTrue(finalized);
        assertGt(totalEmission, 0);
        assertEq(snapshotWeight, aliceWeight);

        // 5. Alice claims her DMD
        vm.prank(alice);
        distributor.claim(0);

        assertEq(dmdToken.balanceOf(alice), totalEmission);

        // 6. Wait for lock to expire (12 months)
        vm.warp(block.timestamp + (12 * 30 days));

        assertTrue(vault.isUnlocked(alice, positionId));

        // 7. Alice redeems: burns DMD to unlock WBTC
        uint256 requiredBurn = redemptionEngine.getRequiredBurn(alice, positionId);
        
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), requiredBurn);
        redemptionEngine.redeem(positionId, requiredBurn);
        vm.stopPrank();

        // 8. Verify final state
        assertEq(wbtc.balanceOf(alice), 10 * WBTC_AMOUNT); // Back to original
        assertLt(dmdToken.balanceOf(alice), totalEmission); // Some burned
        assertTrue(redemptionEngine.redeemed(alice, positionId));
    }

    /*//////////////////////////////////////////////////////////////
                          MULTI-USER WORKFLOW
    //////////////////////////////////////////////////////////////*/

    function test_MultiUser_ProportionalDistribution() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Alice locks 1 WBTC for 6 months (weight: 1.12x)
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 6);
        vm.stopPrank();

        // Bob locks 2 WBTC for 12 months (weight: 2.48x)
        vm.startPrank(bob);
        wbtc.approve(address(vault), 2 * WBTC_AMOUNT);
        vault.lock(2 * WBTC_AMOUNT, 12);
        vm.stopPrank();

        // Charlie locks 1 WBTC for 24 months (weight: 1.48x)
        vm.startPrank(charlie);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 24);
        vm.stopPrank();

        uint256 aliceWeight = vault.totalWeightOf(alice);
        uint256 bobWeight = vault.totalWeightOf(bob);
        uint256 charlieWeight = vault.totalWeightOf(charlie);
        uint256 totalWeight = vault.totalSystemWeight();

        assertEq(totalWeight, aliceWeight + bobWeight + charlieWeight);

        // Complete epoch
        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        (uint256 totalEmission, , ) = distributor.getEpochData(0);

        // All users claim
        vm.prank(alice);
        distributor.claim(0);

        vm.prank(bob);
        distributor.claim(0);

        vm.prank(charlie);
        distributor.claim(0);

        // Verify proportional distribution
        uint256 aliceExpected = (totalEmission * aliceWeight) / totalWeight;
        uint256 bobExpected = (totalEmission * bobWeight) / totalWeight;
        uint256 charlieExpected = (totalEmission * charlieWeight) / totalWeight;

        assertEq(dmdToken.balanceOf(alice), aliceExpected);
        assertEq(dmdToken.balanceOf(bob), bobExpected);
        assertEq(dmdToken.balanceOf(charlie), charlieExpected);

        // Verify total distribution
        uint256 totalDistributed = dmdToken.balanceOf(alice) + 
                                   dmdToken.balanceOf(bob) + 
                                   dmdToken.balanceOf(charlie);
        
        assertEq(totalDistributed, totalEmission);
    }

    /*//////////////////////////////////////////////////////////////
                          MULTI-EPOCH WORKFLOW
    //////////////////////////////////////////////////////////////*/

    function test_MultiEpoch_ClaimAcrossEpochs() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Alice locks WBTC
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        uint256 aliceWeight = vault.totalWeightOf(alice);

        // Complete and finalize 3 epochs
        uint256[] memory emissions = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
            
            (uint256 emission, , ) = distributor.getEpochData(i);
            emissions[i] = emission;
        }

        // Alice batch claims all epochs
        uint256[] memory epochIds = new uint256[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.prank(alice);
        distributor.claimMultiple(epochIds);

        uint256 totalExpected = emissions[0] + emissions[1] + emissions[2];
        assertEq(dmdToken.balanceOf(alice), totalExpected);
    }

    /*//////////////////////////////////////////////////////////////
                          REDEMPTION WORKFLOW
    //////////////////////////////////////////////////////////////*/

    function test_Redemption_MultiplePositions() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Alice creates 3 positions with different durations
        vm.startPrank(alice);
        wbtc.approve(address(vault), 3 * WBTC_AMOUNT);
        uint256 pos1 = vault.lock(WBTC_AMOUNT, 1);
        uint256 pos2 = vault.lock(WBTC_AMOUNT, 6);
        uint256 pos3 = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        // Complete epochs and Alice claims
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
            
            vm.prank(alice);
            distributor.claim(i);
        }

        uint256 dmdBalance = dmdToken.balanceOf(alice);

        // Redeem positions as they unlock
        vm.warp(block.timestamp + 30 days); // Unlock pos1

        uint256 burn1 = redemptionEngine.getRequiredBurn(alice, pos1);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn1);
        redemptionEngine.redeem(pos1, burn1);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos1));
        assertLt(dmdToken.balanceOf(alice), dmdBalance);

        // Unlock and redeem pos2
        vm.warp(block.timestamp + (5 * 30 days));

        uint256 burn2 = redemptionEngine.getRequiredBurn(alice, pos2);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn2);
        redemptionEngine.redeem(pos2, burn2);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos2));

        // Unlock and redeem pos3
        vm.warp(block.timestamp + (6 * 30 days));

        uint256 burn3 = redemptionEngine.getRequiredBurn(alice, pos3);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn3);
        redemptionEngine.redeem(pos3, burn3);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos3));

        // Verify all WBTC returned
        assertEq(wbtc.balanceOf(alice), 10 * WBTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          VESTING INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_VestingIntegration_WithEmissions() public {
        // Setup vesting
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, 1_000_000e18);
        vesting.startVesting();
        vm.stopPrank();

        // Fund vesting contract
        vm.prank(address(distributor));
        dmdToken.mint(address(vesting), 1_000_000e18);

        // Start emissions
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Alice locks and participates in emissions
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        // Foundation claims vesting
        uint256 vestingClaimable = vesting.getClaimable(foundation);
        vm.prank(foundation);
        vesting.claim();

        // Verify both systems working
        assertGt(dmdToken.balanceOf(alice), 0);
        assertEq(dmdToken.balanceOf(foundation), vestingClaimable);
        
        // Verify total minted is sum of both
        uint256 totalMinted = dmdToken.totalMinted();
        assertEq(totalMinted, 1_000_000e18 + dmdToken.balanceOf(alice));
    }

    /*//////////////////////////////////////////////////////////////
                          SUPPLY CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    function test_SupplyConsistency_AcrossOperations() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Multiple users lock
        vm.prank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(alice);
        uint256 alicePos = vault.lock(WBTC_AMOUNT, 12);

        vm.prank(bob);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(bob);
        uint256 bobPos = vault.lock(WBTC_AMOUNT, 12);

        // Complete epoch and claim
        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        vm.prank(bob);
        distributor.claim(0);

        uint256 totalMinted = dmdToken.totalMinted();
        uint256 circulatingSupply = dmdToken.circulatingSupply();
        
        assertEq(totalMinted, circulatingSupply);
        assertEq(dmdToken.totalBurned(), 0);

        // Alice redeems
        vm.warp(block.timestamp + (12 * 30 days));

        uint256 burnAmount = redemptionEngine.getRequiredBurn(alice, alicePos);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burnAmount);
        redemptionEngine.redeem(alicePos, burnAmount);
        vm.stopPrank();

        // Verify supply consistency after burn
        assertEq(dmdToken.totalBurned(), burnAmount);
        assertEq(dmdToken.circulatingSupply(), totalMinted - burnAmount);
        assertEq(
            dmdToken.totalSupply(),
            dmdToken.balanceOf(alice) + dmdToken.balanceOf(bob)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_ZeroWeightUser() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Only Alice locks
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        // Bob tries to claim with no weight
        assertEq(vault.totalWeightOf(bob), 0);

        vm.prank(bob);
        vm.expectRevert(MintDistributor.NoWeight.selector);
        distributor.claim(0);

        // Alice can claim
        vm.prank(alice);
        distributor.claim(0);
        assertGt(dmdToken.balanceOf(alice), 0);
    }

    function test_EdgeCase_ClaimBeforeFinalization() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        // Try to claim before epoch finalized
        vm.prank(alice);
        vm.expectRevert(MintDistributor.EpochNotFinalized.selector);
        distributor.claim(0);
    }

    function test_EdgeCase_RedeemBeforeUnlock() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        // Try to redeem before lock expires
        uint256 burnAmount = redemptionEngine.getRequiredBurn(alice, positionId);
        
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burnAmount);
        vm.expectRevert(RedemptionEngine.PositionLocked.selector);
        redemptionEngine.redeem(positionId, burnAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          STRESS TEST
    //////////////////////////////////////////////////////////////*/

    function test_StressTest_ManyEpochsManyUsers() public {
        vm.prank(owner);
        scheduler.startEmissions();
        
        vm.prank(owner);
        distributor.startDistribution();

        // Three users lock
        vm.prank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(alice);
        vault.lock(WBTC_AMOUNT, 12);

        vm.prank(bob);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(bob);
        vault.lock(WBTC_AMOUNT, 12);

        vm.prank(charlie);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(charlie);
        vault.lock(WBTC_AMOUNT, 12);

        // Run through 10 epochs
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();

            vm.prank(alice);
            distributor.claim(i);

            vm.prank(bob);
            distributor.claim(i);

            vm.prank(charlie);
            distributor.claim(i);
        }

        // Verify all got same amount (equal weights)
        assertEq(dmdToken.balanceOf(alice), dmdToken.balanceOf(bob));
        assertEq(dmdToken.balanceOf(bob), dmdToken.balanceOf(charlie));

        // Verify total emissions
        uint256 totalEmitted = scheduler.totalEmitted();
        uint256 totalDistributed = dmdToken.balanceOf(alice) + 
                                   dmdToken.balanceOf(bob) + 
                                   dmdToken.balanceOf(charlie);
        
        assertEq(totalDistributed, totalEmitted);
    }
}