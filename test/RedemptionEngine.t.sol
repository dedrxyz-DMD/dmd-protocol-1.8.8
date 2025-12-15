// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/RedemptionEngine.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalBurned;

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
        
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        
        return true;
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        totalBurned += amount;
    }
}

contract MockBTCReserveVault {
    struct Position {
        address btcAsset;
        uint256 amount;
        uint256 lockMonths;
        uint256 lockTime;
        uint256 weight;
        uint256 unlockTime;
        bool exists;
    }

    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => bool) public redeemCalled;

    function setPosition(
        address user,
        uint256 positionId,
        uint256 amount,
        uint256 lockMonths,
        uint256 lockTime,
        uint256 weight
    ) external {
        positions[user][positionId] = Position({
            btcAsset: address(1),
            amount: amount,
            lockMonths: lockMonths,
            lockTime: lockTime,
            weight: weight,
            unlockTime: lockTime + (lockMonths * 30 days),
            exists: true
        });
    }

    function getPosition(address user, uint256 positionId)
        external
        view
        returns (
            address btcAsset,
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight
        )
    {
        Position memory pos = positions[user][positionId];
        return (pos.btcAsset, pos.amount, pos.lockMonths, pos.unlockTime, pos.weight);
    }

    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (!pos.exists) return false;
        return block.timestamp >= pos.unlockTime;
    }

    function redeem(address user, uint256 positionId) external {
        require(positions[user][positionId].exists, "POSITION_NOT_FOUND");
        redeemCalled[user] = true;
        delete positions[user][positionId];
    }
}

contract RedemptionEngineTest is Test {
    RedemptionEngine public engine;
    MockDMDToken public dmdToken;
    MockBTCReserveVault public vault;

    address public alice;
    address public bob;
    address public charlie;

    uint256 constant WBTC_AMOUNT = 1e8;

    event Redeemed(
        address indexed user,
        uint256 indexed positionId,
        uint256 wbtcAmount,
        uint256 dmdBurned
    );

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        dmdToken = new MockDMDToken();
        vault = new MockBTCReserveVault();

        engine = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(address(engine.dmdToken()), address(dmdToken));
        assertEq(address(engine.vault()), address(vault));
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(RedemptionEngine.InvalidAmount.selector);
        new RedemptionEngine(
            IDMDToken(address(0)),
            IBTCReserveVault(address(vault))
        );
    }

    function test_Constructor_RevertsOnZeroVault() public {
        vm.expectRevert(RedemptionEngine.InvalidAmount.selector);
        new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(0))
        );
    }

    /*//////////////////////////////////////////////////////////////
                          REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_Success() public {
        // Setup position: 1 WBTC, 12 months, weight = 1.24 WBTC
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);

        // Mint DMD to alice and approve
        dmdToken.mint(alice, weight);
        
        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);

        // Warp time to unlock
        vm.warp(block.timestamp + 360 days);

        vm.expectEmit(true, true, false, true);
        emit Redeemed(alice, 0, WBTC_AMOUNT, weight);
        engine.redeem(0, weight);
        vm.stopPrank();

        assertEq(dmdToken.balanceOf(alice), 0);
        assertEq(dmdToken.totalBurned(), weight);
        assertTrue(engine.redeemed(alice, 0));
        assertEq(engine.totalBurnedByUser(alice), weight);
        assertTrue(vault.redeemCalled(alice));
    }

    function test_Redeem_WithExcessBurn() public {
        // Weight is 1.24 WBTC, but user burns 2 WBTC
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        uint256 burnAmount = 2 * WBTC_AMOUNT;
        
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, burnAmount);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), burnAmount);
        vm.warp(block.timestamp + 360 days);
        
        engine.redeem(0, burnAmount);
        vm.stopPrank();

        assertEq(dmdToken.totalBurned(), burnAmount);
        assertTrue(engine.redeemed(alice, 0));
    }

    function test_Redeem_RevertsOnZeroAmount() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);

        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.InvalidAmount.selector);
        engine.redeem(0, 0);
    }

    function test_Redeem_RevertsOnInsufficientBurn() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight - 1);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight - 1);
        vm.warp(block.timestamp + 360 days);

        vm.expectRevert(RedemptionEngine.InsufficientDMD.selector);
        engine.redeem(0, weight - 1);
        vm.stopPrank();
    }

    function test_Redeem_RevertsWhenLocked() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);

        // Don't warp time - position still locked
        vm.expectRevert(RedemptionEngine.PositionLocked.selector);
        engine.redeem(0, weight);
        vm.stopPrank();
    }

    function test_Redeem_RevertsOnInvalidPosition() public {
        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.PositionNotFound.selector);
        engine.redeem(999, 1000e18);
    }

    function test_Redeem_RevertsOnAlreadyRedeemed() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight * 2);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight * 2);
        vm.warp(block.timestamp + 360 days);

        engine.redeem(0, weight);

        vm.expectRevert(RedemptionEngine.AlreadyRedeemed.selector);
        engine.redeem(0, weight);
        vm.stopPrank();
    }

    function test_Redeem_MultiplePositionsSameUser() public {
        uint256 weight1 = (WBTC_AMOUNT * 1020) / 1000; // 1 month
        uint256 weight2 = (WBTC_AMOUNT * 1240) / 1000; // 12 months

        vault.setPosition(alice, 0, WBTC_AMOUNT, 1, block.timestamp, weight1);
        vault.setPosition(alice, 1, WBTC_AMOUNT, 12, block.timestamp, weight2);

        dmdToken.mint(alice, weight1 + weight2);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight1 + weight2);

        // Redeem position 0 after 1 month
        vm.warp(block.timestamp + 30 days);
        engine.redeem(0, weight1);

        assertEq(engine.totalBurnedByUser(alice), weight1);
        assertTrue(engine.redeemed(alice, 0));
        assertFalse(engine.redeemed(alice, 1));

        // Redeem position 1 after 12 months
        vm.warp(block.timestamp + 330 days);
        engine.redeem(1, weight2);

        assertEq(engine.totalBurnedByUser(alice), weight1 + weight2);
        assertTrue(engine.redeemed(alice, 1));
        vm.stopPrank();
    }

    function test_Redeem_MultipleUsers() public {
        uint256 weightAlice = (WBTC_AMOUNT * 1240) / 1000;
        uint256 weightBob = (WBTC_AMOUNT * 1480) / 1000;

        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weightAlice);
        vault.setPosition(bob, 0, WBTC_AMOUNT, 24, block.timestamp, weightBob);

        dmdToken.mint(alice, weightAlice);
        dmdToken.mint(bob, weightBob);

        vm.warp(block.timestamp + 720 days);

        vm.prank(alice);
        dmdToken.approve(address(engine), weightAlice);
        vm.prank(alice);
        engine.redeem(0, weightAlice);

        vm.prank(bob);
        dmdToken.approve(address(engine), weightBob);
        vm.prank(bob);
        engine.redeem(0, weightBob);

        assertTrue(engine.redeemed(alice, 0));
        assertTrue(engine.redeemed(bob, 0));
        assertEq(dmdToken.totalBurned(), weightAlice + weightBob);
    }

    /*//////////////////////////////////////////////////////////////
                          BATCH REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RedeemMultiple_Success() public {
        uint256 weight1 = (WBTC_AMOUNT * 1020) / 1000;
        uint256 weight2 = (WBTC_AMOUNT * 1120) / 1000;
        uint256 weight3 = (WBTC_AMOUNT * 1240) / 1000;

        vault.setPosition(alice, 0, WBTC_AMOUNT, 1, block.timestamp, weight1);
        vault.setPosition(alice, 1, WBTC_AMOUNT, 6, block.timestamp, weight2);
        vault.setPosition(alice, 2, WBTC_AMOUNT, 12, block.timestamp, weight3);

        uint256 totalWeight = weight1 + weight2 + weight3;
        dmdToken.mint(alice, totalWeight);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), totalWeight);
        vm.warp(block.timestamp + 360 days);

        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 0;
        positionIds[1] = 1;
        positionIds[2] = 2;

        uint256[] memory dmdAmounts = new uint256[](3);
        dmdAmounts[0] = weight1;
        dmdAmounts[1] = weight2;
        dmdAmounts[2] = weight3;

        engine.redeemMultiple(positionIds, dmdAmounts);
        vm.stopPrank();

        assertTrue(engine.redeemed(alice, 0));
        assertTrue(engine.redeemed(alice, 1));
        assertTrue(engine.redeemed(alice, 2));
        assertEq(engine.totalBurnedByUser(alice), totalWeight);
        assertEq(dmdToken.totalBurned(), totalWeight);
    }

    function test_RedeemMultiple_SkipsAlreadyRedeemed() public {
        uint256 weight1 = (WBTC_AMOUNT * 1020) / 1000;
        uint256 weight2 = (WBTC_AMOUNT * 1240) / 1000;

        vault.setPosition(alice, 0, WBTC_AMOUNT, 1, block.timestamp, weight1);
        vault.setPosition(alice, 1, WBTC_AMOUNT, 12, block.timestamp, weight2);

        dmdToken.mint(alice, weight1 + weight2);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight1 + weight2);
        vm.warp(block.timestamp + 360 days);

        // Redeem position 0 individually
        engine.redeem(0, weight1);

        // Try batch redeem including position 0 (should skip)
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = 0;
        positionIds[1] = 1;

        uint256[] memory dmdAmounts = new uint256[](2);
        dmdAmounts[0] = weight1;
        dmdAmounts[1] = weight2;

        engine.redeemMultiple(positionIds, dmdAmounts);
        vm.stopPrank();

        // Should have burned weight1 + weight2 total
        assertEq(dmdToken.totalBurned(), weight1 + weight2);
    }

    function test_RedeemMultiple_SkipsLockedPositions() public {
        uint256 weight1 = (WBTC_AMOUNT * 1020) / 1000; // 1 month
        uint256 weight2 = (WBTC_AMOUNT * 1240) / 1000; // 12 months

        vault.setPosition(alice, 0, WBTC_AMOUNT, 1, block.timestamp, weight1);
        vault.setPosition(alice, 1, WBTC_AMOUNT, 12, block.timestamp, weight2);

        dmdToken.mint(alice, weight1 + weight2);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight1 + weight2);
        
        // Only unlock position 0 (1 month)
        vm.warp(block.timestamp + 30 days);

        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = 0;
        positionIds[1] = 1; // Still locked

        uint256[] memory dmdAmounts = new uint256[](2);
        dmdAmounts[0] = weight1;
        dmdAmounts[1] = weight2;

        engine.redeemMultiple(positionIds, dmdAmounts);
        vm.stopPrank();

        // Only position 0 should be redeemed
        assertTrue(engine.redeemed(alice, 0));
        assertFalse(engine.redeemed(alice, 1));
        assertEq(dmdToken.totalBurned(), weight1);
    }

    function test_RedeemMultiple_RevertsOnArrayMismatch() public {
        uint256[] memory positionIds = new uint256[](2);
        uint256[] memory dmdAmounts = new uint256[](3);

        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.InvalidAmount.selector);
        engine.redeemMultiple(positionIds, dmdAmounts);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsRedeemed() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        assertFalse(engine.isRedeemed(alice, 0));

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);
        vm.warp(block.timestamp + 360 days);
        engine.redeem(0, weight);
        vm.stopPrank();

        assertTrue(engine.isRedeemed(alice, 0));
    }

    function test_GetRequiredBurn() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);

        uint256 required = engine.getRequiredBurn(alice, 0);
        assertEq(required, weight);
    }

    function test_GetRequiredBurn_NonExistentPosition() public {
        uint256 required = engine.getRequiredBurn(alice, 999);
        assertEq(required, 0);
    }

    function test_IsRedeemable_AllConditionsMet() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        vm.warp(block.timestamp + 360 days);

        assertTrue(engine.isRedeemable(alice, 0));
    }

    function test_IsRedeemable_AlreadyRedeemed() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);
        vm.warp(block.timestamp + 360 days);
        engine.redeem(0, weight);
        vm.stopPrank();

        assertFalse(engine.isRedeemable(alice, 0));
    }

    function test_IsRedeemable_Locked() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        // Don't warp time
        assertFalse(engine.isRedeemable(alice, 0));
    }

    function test_IsRedeemable_InsufficientDMD() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight - 1);

        vm.warp(block.timestamp + 360 days);

        assertFalse(engine.isRedeemable(alice, 0));
    }

    function test_GetUserRedemptionStats() public {
        uint256 weight = (WBTC_AMOUNT * 1240) / 1000;
        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, weight * 2);

        (uint256 totalBurned, uint256 currentBalance) = engine.getUserRedemptionStats(alice);
        assertEq(totalBurned, 0);
        assertEq(currentBalance, weight * 2);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);
        vm.warp(block.timestamp + 360 days);
        engine.redeem(0, weight);
        vm.stopPrank();

        (totalBurned, currentBalance) = engine.getUserRedemptionStats(alice);
        assertEq(totalBurned, weight);
        assertEq(currentBalance, weight);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Redeem(uint256 wbtcAmount, uint256 lockMonths) public {
        wbtcAmount = bound(wbtcAmount, 1, 10 * WBTC_AMOUNT);
        lockMonths = bound(lockMonths, 1, 24);

        uint256 effectiveMonths = lockMonths > 24 ? 24 : lockMonths;
        uint256 weight = (wbtcAmount * (1000 + (effectiveMonths * 20))) / 1000;

        vault.setPosition(alice, 0, wbtcAmount, lockMonths, block.timestamp, weight);
        dmdToken.mint(alice, weight);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), weight);
        vm.warp(block.timestamp + (lockMonths * 30 days));
        engine.redeem(0, weight);
        vm.stopPrank();

        assertTrue(engine.redeemed(alice, 0));
        assertEq(dmdToken.totalBurned(), weight);
    }

    function testFuzz_RedeemWithExcess(uint256 weight, uint256 burnMultiplier) public {
        weight = bound(weight, 1e18, 1000e18);
        burnMultiplier = bound(burnMultiplier, 1, 10);

        uint256 burnAmount = weight * burnMultiplier;

        vault.setPosition(alice, 0, WBTC_AMOUNT, 12, block.timestamp, weight);
        dmdToken.mint(alice, burnAmount);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), burnAmount);
        vm.warp(block.timestamp + 360 days);
        engine.redeem(0, burnAmount);
        vm.stopPrank();

        assertEq(dmdToken.totalBurned(), burnAmount);
        assertTrue(engine.redeemed(alice, 0));
    }
}