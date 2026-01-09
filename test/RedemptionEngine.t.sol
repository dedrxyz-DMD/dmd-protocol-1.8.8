// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {RedemptionEngine, IDMDToken, IBTCReserveVault, IMintDistributor} from "../src/RedemptionEngine.sol";

contract MockDMDToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockBTCReserveVault {
    struct Position {
        uint256 tbtcAmount;
        uint256 lockStart;
        uint256 lockDuration;
        uint256 weight;
    }
    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => mapping(uint256 => bool)) public unlocked;

    function setPosition(address user, uint256 posId, uint256 tbtc, uint256 weight) external {
        positions[user][posId] = Position({
            tbtcAmount: tbtc,
            lockStart: block.timestamp,
            lockDuration: 30 days,
            weight: weight
        });
    }

    function setUnlocked(address user, uint256 posId, bool _unlocked) external {
        unlocked[user][posId] = _unlocked;
    }

    function getPosition(address user, uint256 posId) external view returns (uint256, uint256, uint256, uint256) {
        Position memory p = positions[user][posId];
        return (p.tbtcAmount, p.lockStart, p.lockDuration, p.weight);
    }

    function isUnlocked(address user, uint256 posId) external view returns (bool) {
        return unlocked[user][posId];
    }

    function redeem(address, uint256) external {}
}

contract MockMintDistributor {
    mapping(address => mapping(uint256 => uint256)) public positionDmdMinted;

    function setPositionDmdMinted(address user, uint256 posId, uint256 amount) external {
        positionDmdMinted[user][posId] = amount;
    }

    function getPositionDmdMinted(address user, uint256 posId) external view returns (uint256) {
        return positionDmdMinted[user][posId];
    }
}

contract RedemptionEngineTest is Test {
    RedemptionEngine public engine;
    MockDMDToken public dmdToken;
    MockBTCReserveVault public vault;
    MockMintDistributor public distributor;

    address public alice;
    address public bob;

    event Redeemed(address indexed user, uint256 indexed positionId, uint256 tbtcAmount, uint256 dmdBurned);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        dmdToken = new MockDMDToken();
        vault = new MockBTCReserveVault();
        distributor = new MockMintDistributor();

        engine = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IMintDistributor(address(distributor))
        );
    }

    function test_Constructor() public view {
        assertEq(address(engine.DMD_TOKEN()), address(dmdToken));
        assertEq(address(engine.VAULT()), address(vault));
        assertEq(address(engine.MINT_DISTRIBUTOR()), address(distributor));
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(RedemptionEngine.ZeroAddressNotAllowed.selector);
        new RedemptionEngine(
            IDMDToken(address(0)),
            IBTCReserveVault(address(vault)),
            IMintDistributor(address(distributor))
        );
    }

    function test_Constructor_RevertsOnZeroVault() public {
        vm.expectRevert(RedemptionEngine.ZeroAddressNotAllowed.selector);
        new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(0)),
            IMintDistributor(address(distributor))
        );
    }

    function test_Redeem_Success() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, true);
        distributor.setPositionDmdMinted(alice, 0, 50e18);
        dmdToken.mint(alice, 50e18);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), 50e18);

        vm.expectEmit(true, true, false, true);
        emit Redeemed(alice, 0, 1e18, 50e18);
        engine.redeem(0);
        vm.stopPrank();

        assertEq(dmdToken.balanceOf(alice), 0);
        assertTrue(engine.isRedeemed(alice, 0));
    }

    function test_Redeem_FreeIfNoDMDMinted() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, true);
        distributor.setPositionDmdMinted(alice, 0, 0);

        vm.prank(alice);
        engine.redeem(0);

        assertTrue(engine.isRedeemed(alice, 0));
    }

    function test_Redeem_RevertsOnPositionLocked() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, false);

        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.PositionLocked.selector);
        engine.redeem(0);
    }

    function test_Redeem_RevertsOnPositionNotFound() public {
        vault.setUnlocked(alice, 0, true);

        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.PositionNotFound.selector);
        engine.redeem(0);
    }

    function test_Redeem_RevertsOnAlreadyRedeemed() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, true);
        distributor.setPositionDmdMinted(alice, 0, 0);

        vm.prank(alice);
        engine.redeem(0);

        vm.prank(alice);
        vm.expectRevert(RedemptionEngine.AlreadyRedeemed.selector);
        engine.redeem(0);
    }

    function test_RedeemMultiple_Success() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setPosition(alice, 1, 2e18, 200e18);
        vault.setUnlocked(alice, 0, true);
        vault.setUnlocked(alice, 1, true);
        distributor.setPositionDmdMinted(alice, 0, 50e18);
        distributor.setPositionDmdMinted(alice, 1, 100e18);
        dmdToken.mint(alice, 150e18);

        vm.startPrank(alice);
        dmdToken.approve(address(engine), 150e18);

        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = 0;
        positionIds[1] = 1;

        engine.redeemMultiple(positionIds);
        vm.stopPrank();

        assertEq(dmdToken.balanceOf(alice), 0);
        assertTrue(engine.isRedeemed(alice, 0));
        assertTrue(engine.isRedeemed(alice, 1));
    }

    function test_IsRedeemable() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, true);
        distributor.setPositionDmdMinted(alice, 0, 50e18);
        dmdToken.mint(alice, 50e18);

        assertTrue(engine.isRedeemable(alice, 0));
    }

    function test_IsRedeemable_FalseAfterRedeemed() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        vault.setUnlocked(alice, 0, true);
        distributor.setPositionDmdMinted(alice, 0, 0);

        vm.prank(alice);
        engine.redeem(0);

        assertFalse(engine.isRedeemable(alice, 0));
    }

    function test_GetRequiredBurn() public {
        vault.setPosition(alice, 0, 1e18, 100e18);
        distributor.setPositionDmdMinted(alice, 0, 50e18);

        assertEq(engine.getRequiredBurn(alice, 0), 50e18);
    }
}
