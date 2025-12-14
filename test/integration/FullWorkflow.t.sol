// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/DMDToken.sol";
import "../../src/BTCReserveVault.sol";
import "../../src/EmissionScheduler.sol";
import "../../src/MintDistributor.sol";
import "../../src/RedemptionEngine.sol";
import "../../src/VestingContract.sol";

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
    DMDToken public dmdToken;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    RedemptionEngine public redemptionEngine;
    VestingContract public vesting;
    MockWBTC public wbtc;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public foundation;

    uint256 constant WBTC_AMOUNT = 1e8;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        foundation = makeAddr("foundation");

        wbtc = new MockWBTC();

        vm.startPrank(owner);

        address tempDistributor = makeAddr("tempDistributor");
        scheduler = new EmissionScheduler(owner, tempDistributor);
        dmdToken = new DMDToken(tempDistributor);
        
        address tempVault = makeAddr("tempVault");
        redemptionEngine = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(tempVault)
        );

        vault = new BTCReserveVault(address(wbtc), address(redemptionEngine));

        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );

        dmdToken = new DMDToken(address(distributor));
        scheduler = new EmissionScheduler(owner, address(distributor));

        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );

        dmdToken = new DMDToken(address(distributor));
        vesting = new VestingContract(owner, IDMDToken(address(dmdToken)));

        scheduler.startEmissions();
        distributor.startDistribution();

        vm.stopPrank();

        wbtc.mint(alice, 10 * WBTC_AMOUNT);
        wbtc.mint(bob, 10 * WBTC_AMOUNT);
        wbtc.mint(charlie, 10 * WBTC_AMOUNT);
    }

    function test_HappyPath_SingleUser() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        uint256 aliceWeight = vault.calculateWeight(WBTC_AMOUNT, 12);
        assertEq(vault.totalWeightOf(alice), aliceWeight);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        (uint256 totalEmission, uint256 snapshotWeight, bool finalized) = 
            distributor.getEpochData(0);
        
        assertTrue(finalized);
        assertGt(totalEmission, 0);
        assertEq(snapshotWeight, aliceWeight);

        vm.prank(alice);
        distributor.claim(0);

        assertEq(dmdToken.balanceOf(alice), totalEmission);

        vm.warp(block.timestamp + (12 * 30 days));

        assertTrue(vault.isUnlocked(alice, positionId));

        uint256 requiredBurn = redemptionEngine.getRequiredBurn(alice, positionId);
        
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), requiredBurn);
        redemptionEngine.redeem(positionId, requiredBurn);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(alice), 10 * WBTC_AMOUNT);
        assertLt(dmdToken.balanceOf(alice), totalEmission);
        assertTrue(redemptionEngine.redeemed(alice, positionId));
    }

    function test_MultiUser_ProportionalDistribution() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 6);
        vm.stopPrank();

        vm.startPrank(bob);
        wbtc.approve(address(vault), 2 * WBTC_AMOUNT);
        vault.lock(2 * WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.startPrank(charlie);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 24);
        vm.stopPrank();

        uint256 aliceWeight = vault.totalWeightOf(alice);
        uint256 bobWeight = vault.totalWeightOf(bob);
        uint256 charlieWeight = vault.totalWeightOf(charlie);
        uint256 totalWeight = vault.totalSystemWeight();

        assertEq(totalWeight, aliceWeight + bobWeight + charlieWeight);

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        (uint256 totalEmission, , ) = distributor.getEpochData(0);

        vm.prank(alice);
        distributor.claim(0);

        vm.prank(bob);
        distributor.claim(0);

        vm.prank(charlie);
        distributor.claim(0);

        uint256 aliceExpected = (totalEmission * aliceWeight) / totalWeight;
        uint256 bobExpected = (totalEmission * bobWeight) / totalWeight;
        uint256 charlieExpected = (totalEmission * charlieWeight) / totalWeight;

        assertEq(dmdToken.balanceOf(alice), aliceExpected);
        assertEq(dmdToken.balanceOf(bob), bobExpected);
        assertEq(dmdToken.balanceOf(charlie), charlieExpected);

        uint256 totalDistributed = dmdToken.balanceOf(alice) + 
                                   dmdToken.balanceOf(bob) + 
                                   dmdToken.balanceOf(charlie);
        
        assertEq(totalDistributed, totalEmission);
    }

    function test_MultiEpoch_ClaimAcrossEpochs() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        uint256[] memory emissions = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
            
            (uint256 emission, , ) = distributor.getEpochData(i);
            emissions[i] = emission;
        }

        uint256[] memory epochIds = new uint256[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.prank(alice);
        distributor.claimMultiple(epochIds);

        uint256 totalExpected = emissions[0] + emissions[1] + emissions[2];
        assertEq(dmdToken.balanceOf(alice), totalExpected);
    }

    function test_Redemption_MultiplePositions() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), 3 * WBTC_AMOUNT);
        uint256 pos1 = vault.lock(WBTC_AMOUNT, 1);
        uint256 pos2 = vault.lock(WBTC_AMOUNT, 6);
        uint256 pos3 = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 7 days);
            distributor.finalizeEpoch();
            
            vm.prank(alice);
            distributor.claim(i);
        }

        uint256 dmdBalance = dmdToken.balanceOf(alice);

        vm.warp(block.timestamp + 30 days);

        uint256 burn1 = redemptionEngine.getRequiredBurn(alice, pos1);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn1);
        redemptionEngine.redeem(pos1, burn1);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos1));
        assertLt(dmdToken.balanceOf(alice), dmdBalance);

        vm.warp(block.timestamp + (5 * 30 days));

        uint256 burn2 = redemptionEngine.getRequiredBurn(alice, pos2);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn2);
        redemptionEngine.redeem(pos2, burn2);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos2));

        vm.warp(block.timestamp + (6 * 30 days));

        uint256 burn3 = redemptionEngine.getRequiredBurn(alice, pos3);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burn3);
        redemptionEngine.redeem(pos3, burn3);
        vm.stopPrank();

        assertTrue(redemptionEngine.redeemed(alice, pos3));
        assertEq(wbtc.balanceOf(alice), 10 * WBTC_AMOUNT);
    }

    function test_VestingIntegration_WithEmissions() public {
        vm.startPrank(owner);
        vesting.addBeneficiary(foundation, 1_000_000e18);
        vesting.startVesting();
        vm.stopPrank();

        vm.prank(address(distributor));
        dmdToken.mint(address(vesting), 1_000_000e18);

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        uint256 vestingClaimable = vesting.getClaimable(foundation);
        vm.prank(foundation);
        vesting.claim();

        assertGt(dmdToken.balanceOf(alice), 0);
        assertEq(dmdToken.balanceOf(foundation), vestingClaimable);
        
        uint256 totalMinted = dmdToken.totalMinted();
        assertEq(totalMinted, 1_000_000e18 + dmdToken.balanceOf(alice));
    }

    function test_SupplyConsistency_AcrossOperations() public {
        vm.prank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(alice);
        uint256 alicePos = vault.lock(WBTC_AMOUNT, 12);

        vm.prank(bob);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(bob);
        vault.lock(WBTC_AMOUNT, 12);

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

        vm.warp(block.timestamp + (12 * 30 days));

        uint256 burnAmount = redemptionEngine.getRequiredBurn(alice, alicePos);
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burnAmount);
        redemptionEngine.redeem(alicePos, burnAmount);
        vm.stopPrank();

        assertEq(dmdToken.totalBurned(), burnAmount);
        assertEq(dmdToken.circulatingSupply(), totalMinted - burnAmount);
        assertEq(
            dmdToken.totalSupply(),
            dmdToken.balanceOf(alice) + dmdToken.balanceOf(bob)
        );
    }

    function test_EdgeCase_ZeroWeightUser() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        assertEq(vault.totalWeightOf(bob), 0);

        vm.prank(bob);
        vm.expectRevert(MintDistributor.NoWeight.selector);
        distributor.claim(0);

        vm.prank(alice);
        distributor.claim(0);
        assertGt(dmdToken.balanceOf(alice), 0);
    }

    function test_EdgeCase_ClaimBeforeFinalization() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(MintDistributor.EpochNotFinalized.selector);
        distributor.claim(0);
    }

    function test_EdgeCase_RedeemBeforeUnlock() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        distributor.finalizeEpoch();

        vm.prank(alice);
        distributor.claim(0);

        uint256 burnAmount = redemptionEngine.getRequiredBurn(alice, positionId);
        
        vm.startPrank(alice);
        dmdToken.approve(address(redemptionEngine), burnAmount);
        vm.expectRevert(RedemptionEngine.PositionLocked.selector);
        redemptionEngine.redeem(positionId, burnAmount);
        vm.stopPrank();
    }

    function test_StressTest_ManyEpochsManyUsers() public {
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

        assertEq(dmdToken.balanceOf(alice), dmdToken.balanceOf(bob));
        assertEq(dmdToken.balanceOf(bob), dmdToken.balanceOf(charlie));

        uint256 totalEmitted = scheduler.totalEmitted();
        uint256 totalDistributed = dmdToken.balanceOf(alice) + 
                                   dmdToken.balanceOf(bob) + 
                                   dmdToken.balanceOf(charlie);
        
        assertEq(totalDistributed, totalEmitted);
    }
}
