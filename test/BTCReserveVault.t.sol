// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/BTCReserveVault.sol";

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

contract BTCReserveVaultTest is Test {
    BTCReserveVault public vault;
    MockWBTC public wbtc;

    address public redemptionEngine;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant WBTC_AMOUNT = 1e8; // 1 WBTC (8 decimals)

    event Locked(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 lockMonths,
        uint256 weight
    );

    event Redeemed(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount
    );

    function setUp() public {
        wbtc = new MockWBTC();
        redemptionEngine = makeAddr("redemptionEngine");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        vault = new BTCReserveVault(address(wbtc), redemptionEngine);

        // Fund test users
        wbtc.mint(alice, 10 * WBTC_AMOUNT);
        wbtc.mint(bob, 10 * WBTC_AMOUNT);
        wbtc.mint(charlie, 10 * WBTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(vault.wbtc(), address(wbtc));
        assertEq(vault.redemptionEngine(), redemptionEngine);
        assertEq(vault.totalLockedWBTC(), 0);
        assertEq(vault.totalSystemWeight(), 0);
    }

    function test_Constructor_RevertsOnZeroWBTC() public {
        vm.expectRevert(BTCReserveVault.InvalidAmount.selector);
        new BTCReserveVault(address(0), redemptionEngine);
    }

    function test_Constructor_RevertsOnZeroRedemptionEngine() public {
        vm.expectRevert(BTCReserveVault.InvalidAmount.selector);
        new BTCReserveVault(address(wbtc), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Lock_OneMonth() public {
        uint256 lockMonths = 1;
        uint256 expectedWeight = vault.calculateWeight(WBTC_AMOUNT, lockMonths);

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        
        vm.expectEmit(true, true, false, true);
        emit Locked(alice, 0, WBTC_AMOUNT, lockMonths, expectedWeight);
        uint256 positionId = vault.lock(WBTC_AMOUNT, lockMonths);
        vm.stopPrank();

        assertEq(positionId, 0);
        assertEq(vault.totalWeightOf(alice), expectedWeight);
        assertEq(vault.totalLockedWBTC(), WBTC_AMOUNT);
        assertEq(vault.totalSystemWeight(), expectedWeight);

        (uint256 amount, uint256 months, uint256 lockTime, uint256 weight, ) = 
            vault.getPosition(alice, positionId);
        
        assertEq(amount, WBTC_AMOUNT);
        assertEq(months, lockMonths);
        assertEq(lockTime, block.timestamp);
        assertEq(weight, expectedWeight);
    }

    function test_Lock_TwelveMonths() public {
        uint256 lockMonths = 12;
        uint256 expectedWeight = vault.calculateWeight(WBTC_AMOUNT, lockMonths);

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, lockMonths);
        vm.stopPrank();

        assertEq(vault.totalWeightOf(alice), expectedWeight);
        
        // Weight = amount * (1.0 + 0.02 * 12) = amount * 1.24
        uint256 expectedCalc = (WBTC_AMOUNT * 1240) / 1000;
        assertEq(expectedWeight, expectedCalc);
    }

    function test_Lock_TwentyFourMonths_MaxWeight() public {
        uint256 lockMonths = 24;
        uint256 expectedWeight = vault.calculateWeight(WBTC_AMOUNT, lockMonths);

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, lockMonths);
        vm.stopPrank();

        // Weight = amount * (1.0 + 0.02 * 24) = amount * 1.48
        uint256 expectedCalc = (WBTC_AMOUNT * 1480) / 1000;
        assertEq(expectedWeight, expectedCalc);
    }

    function test_Lock_ThirtySixMonths_WeightCapped() public {
        uint256 lockMonths = 36;
        uint256 expectedWeight = vault.calculateWeight(WBTC_AMOUNT, lockMonths);

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, lockMonths);
        vm.stopPrank();

        // Weight capped at 24 months = 1.48x
        uint256 maxWeight = (WBTC_AMOUNT * 1480) / 1000;
        assertEq(expectedWeight, maxWeight);
    }

    function test_Lock_MultiplePositions() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), 3 * WBTC_AMOUNT);
        
        uint256 pos1 = vault.lock(WBTC_AMOUNT, 1);
        uint256 pos2 = vault.lock(WBTC_AMOUNT, 12);
        uint256 pos3 = vault.lock(WBTC_AMOUNT, 24);
        vm.stopPrank();

        assertEq(pos1, 0);
        assertEq(pos2, 1);
        assertEq(pos3, 2);
        assertEq(vault.positionCount(alice), 3);

        uint256 weight1 = vault.calculateWeight(WBTC_AMOUNT, 1);
        uint256 weight12 = vault.calculateWeight(WBTC_AMOUNT, 12);
        uint256 weight24 = vault.calculateWeight(WBTC_AMOUNT, 24);
        uint256 totalWeight = weight1 + weight12 + weight24;

        assertEq(vault.totalWeightOf(alice), totalWeight);
        assertEq(vault.totalLockedWBTC(), 3 * WBTC_AMOUNT);
    }

    function test_Lock_MultipleUsers() public {
        vm.prank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(alice);
        vault.lock(WBTC_AMOUNT, 12);

        vm.prank(bob);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        vm.prank(bob);
        vault.lock(WBTC_AMOUNT, 6);

        uint256 aliceWeight = vault.calculateWeight(WBTC_AMOUNT, 12);
        uint256 bobWeight = vault.calculateWeight(WBTC_AMOUNT, 6);

        assertEq(vault.totalWeightOf(alice), aliceWeight);
        assertEq(vault.totalWeightOf(bob), bobWeight);
        assertEq(vault.totalSystemWeight(), aliceWeight + bobWeight);
        assertEq(vault.totalLockedWBTC(), 2 * WBTC_AMOUNT);
    }

    function test_Lock_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(BTCReserveVault.InvalidAmount.selector);
        vault.lock(0, 12);
    }

    function test_Lock_RevertsOnZeroDuration() public {
        vm.prank(alice);
        vm.expectRevert(BTCReserveVault.InvalidDuration.selector);
        vault.lock(WBTC_AMOUNT, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          WEIGHT CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CalculateWeight_OneMonth() public {
        uint256 weight = vault.calculateWeight(WBTC_AMOUNT, 1);
        uint256 expected = (WBTC_AMOUNT * 1020) / 1000; // 1.02x
        assertEq(weight, expected);
    }

    function test_CalculateWeight_TwelveMonths() public {
        uint256 weight = vault.calculateWeight(WBTC_AMOUNT, 12);
        uint256 expected = (WBTC_AMOUNT * 1240) / 1000; // 1.24x
        assertEq(weight, expected);
    }

    function test_CalculateWeight_TwentyFourMonths() public {
        uint256 weight = vault.calculateWeight(WBTC_AMOUNT, 24);
        uint256 expected = (WBTC_AMOUNT * 1480) / 1000; // 1.48x
        assertEq(weight, expected);
    }

    function test_CalculateWeight_BeyondCap() public {
        uint256 weight36 = vault.calculateWeight(WBTC_AMOUNT, 36);
        uint256 weight24 = vault.calculateWeight(WBTC_AMOUNT, 24);
        assertEq(weight36, weight24); // Capped at 24 months
    }

    /*//////////////////////////////////////////////////////////////
                          REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_Success() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 1);
        vm.stopPrank();

        uint256 weight = vault.calculateWeight(WBTC_AMOUNT, 1);

        // Warp time to unlock
        vm.warp(block.timestamp + 30 days);

        assertTrue(vault.isUnlocked(alice, positionId));

        vm.prank(redemptionEngine);
        vm.expectEmit(true, true, false, true);
        emit Redeemed(alice, positionId, WBTC_AMOUNT);
        vault.redeem(alice, positionId);

        assertEq(wbtc.balanceOf(alice), 10 * WBTC_AMOUNT); // Back to original
        assertEq(vault.totalWeightOf(alice), 0);
        assertEq(vault.totalLockedWBTC(), 0);
        assertEq(vault.totalSystemWeight(), 0);

        (uint256 amount, , , , ) = vault.getPosition(alice, positionId);
        assertEq(amount, 0); // Position deleted
    }

    function test_Redeem_RevertsOnUnauthorized() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        vm.expectRevert(BTCReserveVault.Unauthorized.selector);
        vault.redeem(alice, positionId);
    }

    function test_Redeem_RevertsWhenLocked() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        assertFalse(vault.isUnlocked(alice, positionId));

        vm.prank(redemptionEngine);
        vm.expectRevert(BTCReserveVault.LockNotExpired.selector);
        vault.redeem(alice, positionId);
    }

    function test_Redeem_RevertsOnInvalidPosition() public {
        vm.prank(redemptionEngine);
        vm.expectRevert(BTCReserveVault.PositionNotFound.selector);
        vault.redeem(alice, 999);
    }

    function test_Redeem_MultiplePositions() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), 3 * WBTC_AMOUNT);
        uint256 pos1 = vault.lock(WBTC_AMOUNT, 1);
        uint256 pos2 = vault.lock(WBTC_AMOUNT, 2);
        uint256 pos3 = vault.lock(WBTC_AMOUNT, 3);
        vm.stopPrank();

        uint256 weight1 = vault.calculateWeight(WBTC_AMOUNT, 1);
        uint256 weight2 = vault.calculateWeight(WBTC_AMOUNT, 2);

        // Redeem first position after 1 month
        vm.warp(block.timestamp + 30 days);
        vm.prank(redemptionEngine);
        vault.redeem(alice, pos1);

        assertEq(vault.totalWeightOf(alice), vault.calculateWeight(WBTC_AMOUNT, 2) + vault.calculateWeight(WBTC_AMOUNT, 3));
        assertEq(vault.totalLockedWBTC(), 2 * WBTC_AMOUNT);

        // Redeem second position after 2 months total
        vm.warp(block.timestamp + 30 days);
        vm.prank(redemptionEngine);
        vault.redeem(alice, pos2);

        assertEq(vault.totalWeightOf(alice), vault.calculateWeight(WBTC_AMOUNT, 3));
        assertEq(vault.totalLockedWBTC(), WBTC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetUserWeight() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), 2 * WBTC_AMOUNT);
        vault.lock(WBTC_AMOUNT, 6);
        vault.lock(WBTC_AMOUNT, 12);
        vm.stopPrank();

        uint256 weight6 = vault.calculateWeight(WBTC_AMOUNT, 6);
        uint256 weight12 = vault.calculateWeight(WBTC_AMOUNT, 12);
        uint256 totalWeight = weight6 + weight12;

        assertEq(vault.getUserWeight(alice), totalWeight);
    }

    function test_IsUnlocked() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, 6);
        vm.stopPrank();

        assertFalse(vault.isUnlocked(alice, positionId));

        vm.warp(block.timestamp + 179 days);
        assertFalse(vault.isUnlocked(alice, positionId));

        vm.warp(block.timestamp + 1 days); // 180 days total
        assertTrue(vault.isUnlocked(alice, positionId));
    }

    function test_GetPosition() public {
        uint256 lockTime = block.timestamp;
        uint256 lockMonths = 12;

        vm.startPrank(alice);
        wbtc.approve(address(vault), WBTC_AMOUNT);
        uint256 positionId = vault.lock(WBTC_AMOUNT, lockMonths);
        vm.stopPrank();

        (
            uint256 amount,
            uint256 months,
            uint256 posLockTime,
            uint256 weight,
            uint256 unlockTime
        ) = vault.getPosition(alice, positionId);

        assertEq(amount, WBTC_AMOUNT);
        assertEq(months, lockMonths);
        assertEq(posLockTime, lockTime);
        assertEq(weight, vault.calculateWeight(WBTC_AMOUNT, lockMonths));
        assertEq(unlockTime, lockTime + (lockMonths * 30 days));
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Lock(uint256 amount, uint256 lockMonths) public {
        amount = bound(amount, 1, 100 * WBTC_AMOUNT);
        lockMonths = bound(lockMonths, 1, 120);

        wbtc.mint(alice, amount);

        vm.startPrank(alice);
        wbtc.approve(address(vault), amount);
        uint256 positionId = vault.lock(amount, lockMonths);
        vm.stopPrank();

        uint256 expectedWeight = vault.calculateWeight(amount, lockMonths);
        assertEq(vault.totalWeightOf(alice), expectedWeight);
        assertEq(vault.totalLockedWBTC(), amount);
    }

    function testFuzz_CalculateWeight(uint256 amount, uint256 lockMonths) public {
        amount = bound(amount, 1, type(uint128).max);
        lockMonths = bound(lockMonths, 1, 120);

        uint256 weight = vault.calculateWeight(amount, lockMonths);

        uint256 effectiveMonths = lockMonths > 24 ? 24 : lockMonths;
        uint256 expectedWeight = (amount * (1000 + (effectiveMonths * 20))) / 1000;

        assertEq(weight, expectedWeight);
    }

    function testFuzz_Redeem(uint256 amount, uint256 lockMonths) public {
        amount = bound(amount, 1, 10 * WBTC_AMOUNT);
        lockMonths = bound(lockMonths, 1, 24);

        wbtc.mint(alice, amount);

        vm.startPrank(alice);
        wbtc.approve(address(vault), amount);
        uint256 positionId = vault.lock(amount, lockMonths);
        vm.stopPrank();

        vm.warp(block.timestamp + (lockMonths * 30 days));

        uint256 balanceBefore = wbtc.balanceOf(alice);

        vm.prank(redemptionEngine);
        vault.redeem(alice, positionId);

        assertEq(wbtc.balanceOf(alice), balanceBefore + amount);
        assertEq(vault.totalLockedWBTC(), 0);
    }
}