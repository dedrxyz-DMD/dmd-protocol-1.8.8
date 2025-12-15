// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/BTCReserveVault.sol";
import "../src/BTCAssetRegistry.sol";

contract MockBTCToken {
    string public name;
    uint8 public decimals = 8;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name) {
        name = _name;
    }

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

/**
 * @title BTCReserveVaultMultiAssetTest
 * @notice Comprehensive test suite for multi-asset BTC support
 */
contract BTCReserveVaultMultiAssetTest is Test {
    BTCAssetRegistry public registry;
    BTCReserveVault public vault;
    
    MockBTCToken public wbtc;
    MockBTCToken public cbBTC;
    MockBTCToken public tBTC;
    
    address public redemptionEngine;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant BTC_AMOUNT = 1e8; // 1 BTC (8 decimals)

    event BTCAssetAdded(uint256 indexed assetId, address indexed token, string name);
    event Locked(
        address indexed user,
        address indexed btcAsset,
        uint256 indexed positionId,
        uint256 amount,
        uint256 lockMonths,
        uint256 weight
    );
    event Redeemed(
        address indexed user,
        address indexed btcAsset,
        uint256 indexed positionId,
        uint256 amount
    );

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        redemptionEngine = makeAddr("redemptionEngine");

        // Deploy registry
        registry = new BTCAssetRegistry();

        // Deploy BTC tokens
        wbtc = new MockBTCToken("Wrapped BTC");
        cbBTC = new MockBTCToken("Coinbase BTC");
        tBTC = new MockBTCToken("Threshold BTC");

        // Add assets to registry
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        registry.addBTCAsset(address(tBTC), false, "Threshold BTC");

        // Deploy vault with registry
        vault = new BTCReserveVault(address(registry), redemptionEngine);

        // Fund test users with all BTC types
        wbtc.mint(alice, 10 * BTC_AMOUNT);
        wbtc.mint(bob, 10 * BTC_AMOUNT);
        wbtc.mint(charlie, 10 * BTC_AMOUNT);

        cbBTC.mint(alice, 10 * BTC_AMOUNT);
        cbBTC.mint(bob, 10 * BTC_AMOUNT);
        cbBTC.mint(charlie, 10 * BTC_AMOUNT);

        tBTC.mint(alice, 10 * BTC_AMOUNT);
        tBTC.mint(bob, 10 * BTC_AMOUNT);
        tBTC.mint(charlie, 10 * BTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTI-ASSET LOCKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LockMultipleAssetTypes() public {
        vm.startPrank(alice);
        
        // Lock WBTC
        wbtc.approve(address(vault), BTC_AMOUNT);
        uint256 pos1 = vault.lock(address(wbtc), BTC_AMOUNT, 12);
        
        // Lock cbBTC
        cbBTC.approve(address(vault), BTC_AMOUNT);
        uint256 pos2 = vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        
        // Lock tBTC
        tBTC.approve(address(vault), BTC_AMOUNT);
        uint256 pos3 = vault.lock(address(tBTC), BTC_AMOUNT, 12);
        
        vm.stopPrank();

        // Verify positions
        assertEq(pos1, 0);
        assertEq(pos2, 1);
        assertEq(pos3, 2);
        
        // Each has same weight (same amount, same duration)
        uint256 expectedWeight = vault.calculateWeight(BTC_AMOUNT, 12);
        assertEq(vault.totalWeightOf(alice), expectedWeight * 3);
        
        // Check per-asset balances
        assertEq(vault.getTotalLockedByAsset(address(wbtc)), BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(tBTC)), BTC_AMOUNT);
        
        // Check total
        assertEq(vault.totalLockedWBTC(), 3 * BTC_AMOUNT);
    }

    function test_LockWithDifferentAssetsAndDurations() public {
        vm.startPrank(alice);
        
        // Lock WBTC for 6 months
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 6);
        
        // Lock cbBTC for 12 months
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        
        // Lock tBTC for 24 months (max multiplier)
        tBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(tBTC), BTC_AMOUNT, 24);
        
        vm.stopPrank();

        // Calculate expected weights
        uint256 weight6 = vault.calculateWeight(BTC_AMOUNT, 6);   // 1.12x
        uint256 weight12 = vault.calculateWeight(BTC_AMOUNT, 12); // 1.24x
        uint256 weight24 = vault.calculateWeight(BTC_AMOUNT, 24); // 1.48x
        
        assertEq(vault.totalWeightOf(alice), weight6 + weight12 + weight24);
    }

    function test_GetPositionReturnsCorrectAsset() public {
        vm.startPrank(alice);
        
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        
        vm.stopPrank();

        // Check position 0 (WBTC)
        (
            address btcAsset0,
            uint256 amount0,
            uint256 lockMonths0,
            uint256 unlockTime0,
            uint256 weight0
        ) = vault.getPosition(alice, 0);
        
        assertEq(btcAsset0, address(wbtc));
        assertEq(amount0, BTC_AMOUNT);
        assertEq(lockMonths0, 12);
        
        // Check position 1 (cbBTC)
        (
            address btcAsset1,
            uint256 amount1,
            uint256 lockMonths1,
            uint256 unlockTime1,
            uint256 weight1
        ) = vault.getPosition(alice, 1);
        
        assertEq(btcAsset1, address(cbBTC));
        assertEq(amount1, BTC_AMOUNT);
        assertEq(lockMonths1, 12);
    }

    function test_LockRevertsOnUnapprovedAsset() public {
        // Create new token NOT in registry
        MockBTCToken unauthorizedBTC = new MockBTCToken("Unauthorized BTC");
        unauthorizedBTC.mint(alice, BTC_AMOUNT);

        vm.startPrank(alice);
        unauthorizedBTC.approve(address(vault), BTC_AMOUNT);
        
        vm.expectRevert(BTCReserveVault.BTCAssetNotApproved.selector);
        vault.lock(address(unauthorizedBTC), BTC_AMOUNT, 12);
        
        vm.stopPrank();
    }

    function test_LockRevertsOnDeactivatedAsset() public {
        // Deactivate cbBTC
        registry.deactivateAsset(2); // cbBTC is asset ID 2

        vm.startPrank(alice);
        cbBTC.approve(address(vault), BTC_AMOUNT);
        
        vm.expectRevert(BTCReserveVault.BTCAssetNotApproved.selector);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                MULTI-USER MULTI-ASSET SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_ThreeUsersLockDifferentAssets() public {
        // Alice locks WBTC
        vm.startPrank(alice);
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Bob locks cbBTC
        vm.startPrank(bob);
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Charlie locks tBTC
        vm.startPrank(charlie);
        tBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(tBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Check system state
        uint256 expectedWeight = vault.calculateWeight(BTC_AMOUNT, 12);
        
        assertEq(vault.totalWeightOf(alice), expectedWeight);
        assertEq(vault.totalWeightOf(bob), expectedWeight);
        assertEq(vault.totalWeightOf(charlie), expectedWeight);
        assertEq(vault.totalSystemWeight(), expectedWeight * 3);
        
        // Check per-asset tracking
        assertEq(vault.getTotalLockedByAsset(address(wbtc)), BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(tBTC)), BTC_AMOUNT);
        
        // Total across all assets
        assertEq(vault.totalLockedWBTC(), 3 * BTC_AMOUNT);
    }

    function test_OneUserLocksAllAssetTypes() public {
        vm.startPrank(alice);
        
        // Lock 2 BTC in WBTC
        wbtc.approve(address(vault), 2 * BTC_AMOUNT);
        vault.lock(address(wbtc), 2 * BTC_AMOUNT, 12);
        
        // Lock 3 BTC in cbBTC
        cbBTC.approve(address(vault), 3 * BTC_AMOUNT);
        vault.lock(address(cbBTC), 3 * BTC_AMOUNT, 6);
        
        // Lock 1 BTC in tBTC
        tBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(tBTC), BTC_AMOUNT, 24);
        
        vm.stopPrank();

        // Check per-asset
        assertEq(vault.getTotalLockedByAsset(address(wbtc)), 2 * BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), 3 * BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(tBTC)), BTC_AMOUNT);
        
        // Total = 6 BTC
        assertEq(vault.totalLockedWBTC(), 6 * BTC_AMOUNT);
        
        // Calculate expected total weight
        uint256 weight1 = vault.calculateWeight(2 * BTC_AMOUNT, 12);
        uint256 weight2 = vault.calculateWeight(3 * BTC_AMOUNT, 6);
        uint256 weight3 = vault.calculateWeight(BTC_AMOUNT, 24);
        
        assertEq(vault.totalWeightOf(alice), weight1 + weight2 + weight3);
    }

    /*//////////////////////////////////////////////////////////////
                    REDEMPTION WITH MULTI-ASSET
    //////////////////////////////////////////////////////////////*/

    function test_RedeemReturnsCorrectAsset() public {
        // Alice locks different assets
        vm.startPrank(alice);
        
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        
        vm.stopPrank();

        // Fast forward past unlock time
        vm.warp(block.timestamp + 365 days);

        // Redeem position 0 (WBTC) from redemption engine
        vm.startPrank(redemptionEngine);
        
        uint256 aliceWBTCBefore = wbtc.balanceOf(alice);
        vault.releaseBTC(alice, 0, address(wbtc), BTC_AMOUNT);
        uint256 aliceWBTCAfter = wbtc.balanceOf(alice);
        
        assertEq(aliceWBTCAfter - aliceWBTCBefore, BTC_AMOUNT);
        
        // Redeem position 1 (cbBTC)
        uint256 aliceCbBTCBefore = cbBTC.balanceOf(alice);
        vault.releaseBTC(alice, 1, address(cbBTC), BTC_AMOUNT);
        uint256 aliceCbBTCAfter = cbBTC.balanceOf(alice);
        
        assertEq(aliceCbBTCAfter - aliceCbBTCBefore, BTC_AMOUNT);
        
        vm.stopPrank();
    }

    function test_RedeemRevertsOnWrongAsset() public {
        // Alice locks WBTC
        vm.startPrank(alice);
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        // Try to redeem with wrong asset
        vm.startPrank(redemptionEngine);
        vm.expectRevert(BTCReserveVault.WrongBTCAsset.selector);
        vault.releaseBTC(alice, 0, address(cbBTC), BTC_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    REGISTRY INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddNewAssetAfterDeployment() public {
        // Deploy new BTC asset
        MockBTCToken newBTC = new MockBTCToken("New BTC");
        newBTC.mint(alice, BTC_AMOUNT);

        // Initially can't lock
        vm.startPrank(alice);
        newBTC.approve(address(vault), BTC_AMOUNT);
        vm.expectRevert(BTCReserveVault.BTCAssetNotApproved.selector);
        vault.lock(address(newBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Add to registry
        registry.addBTCAsset(address(newBTC), false, "New BTC");

        // Now can lock
        vm.startPrank(alice);
        vault.lock(address(newBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        assertEq(vault.getTotalLockedByAsset(address(newBTC)), BTC_AMOUNT);
    }

    function test_EmergencyDeactivateAsset() public {
        // Alice locks cbBTC
        vm.startPrank(alice);
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Emergency: cbBTC exploit discovered
        registry.deactivateAsset(2);

        // Can't lock new cbBTC
        vm.startPrank(bob);
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vm.expectRevert(BTCReserveVault.BTCAssetNotApproved.selector);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Alice's existing position unaffected
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), BTC_AMOUNT);
    }

    function test_ReactivateAssetAfterFix() public {
        // Deactivate cbBTC
        registry.deactivateAsset(2);

        // Can't lock
        vm.startPrank(alice);
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vm.expectRevert(BTCReserveVault.BTCAssetNotApproved.selector);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        // Fix applied, reactivate
        registry.activateAsset(2);

        // Can lock again
        vm.startPrank(alice);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), BTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                    TOTAL LOCKED AGGREGATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalLockedAggregatesAllAssets() public {
        vm.startPrank(alice);
        
        // Lock different amounts in different assets
        wbtc.approve(address(vault), 5 * BTC_AMOUNT);
        vault.lock(address(wbtc), 5 * BTC_AMOUNT, 12);
        
        cbBTC.approve(address(vault), 3 * BTC_AMOUNT);
        vault.lock(address(cbBTC), 3 * BTC_AMOUNT, 12);
        
        tBTC.approve(address(vault), 2 * BTC_AMOUNT);
        vault.lock(address(tBTC), 2 * BTC_AMOUNT, 12);
        
        vm.stopPrank();

        // Total should be 10 BTC
        assertEq(vault.totalLockedWBTC(), 10 * BTC_AMOUNT);
        
        // Per-asset tracking
        assertEq(vault.getTotalLockedByAsset(address(wbtc)), 5 * BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), 3 * BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(tBTC)), 2 * BTC_AMOUNT);
    }

    function test_TotalLockedUpdatesOnRedemption() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        
        cbBTC.approve(address(vault), BTC_AMOUNT);
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        vm.stopPrank();

        assertEq(vault.totalLockedWBTC(), 2 * BTC_AMOUNT);

        // Fast forward and redeem one
        vm.warp(block.timestamp + 365 days);
        
        vm.prank(redemptionEngine);
        vault.releaseBTC(alice, 0, address(wbtc), BTC_AMOUNT);

        // Total should decrease
        assertEq(vault.totalLockedWBTC(), BTC_AMOUNT);
        assertEq(vault.getTotalLockedByAsset(address(wbtc)), 0);
        assertEq(vault.getTotalLockedByAsset(address(cbBTC)), BTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_LockMultipleAssets(
        uint256 wbtcAmount,
        uint256 cbBTCAmount,
        uint256 tBTCAmount,
        uint256 lockMonths
    ) public {
        // Bound inputs
        wbtcAmount = bound(wbtcAmount, 1e6, 100 * BTC_AMOUNT);
        cbBTCAmount = bound(cbBTCAmount, 1e6, 100 * BTC_AMOUNT);
        tBTCAmount = bound(tBTCAmount, 1e6, 100 * BTC_AMOUNT);
        lockMonths = bound(lockMonths, 1, 36);

        // Mint tokens
        wbtc.mint(alice, wbtcAmount);
        cbBTC.mint(alice, cbBTCAmount);
        tBTC.mint(alice, tBTCAmount);

        vm.startPrank(alice);
        
        // Lock all three
        wbtc.approve(address(vault), wbtcAmount);
        vault.lock(address(wbtc), wbtcAmount, lockMonths);
        
        cbBTC.approve(address(vault), cbBTCAmount);
        vault.lock(address(cbBTC), cbBTCAmount, lockMonths);
        
        tBTC.approve(address(vault), tBTCAmount);
        vault.lock(address(tBTC), tBTCAmount, lockMonths);
        
        vm.stopPrank();

        // Verify total
        uint256 totalLocked = wbtcAmount + cbBTCAmount + tBTCAmount;
        assertEq(vault.totalLockedWBTC(), totalLocked);
    }

    /*//////////////////////////////////////////////////////////////
                        GAS BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    function test_Gas_LockWithMultipleAssets() public {
        vm.startPrank(alice);
        
        wbtc.approve(address(vault), BTC_AMOUNT);
        uint256 gasBefore = gasleft();
        vault.lock(address(wbtc), BTC_AMOUNT, 12);
        uint256 gas1 = gasBefore - gasleft();
        
        cbBTC.approve(address(vault), BTC_AMOUNT);
        gasBefore = gasleft();
        vault.lock(address(cbBTC), BTC_AMOUNT, 12);
        uint256 gas2 = gasBefore - gasleft();
        
        vm.stopPrank();
        
        emit log_named_uint("Gas for first lock (WBTC)", gas1);
        emit log_named_uint("Gas for second lock (cbBTC)", gas2);
    }
}
