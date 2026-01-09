// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DMDToken} from "../src/DMDToken.sol";

contract DMDTokenTest is Test {
    DMDToken public token;

    address public mintDistributor;
    address public vestingContract;
    address public alice;
    address public bob;
    address public charlie;

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        mintDistributor = makeAddr("mintDistributor");
        vestingContract = makeAddr("vestingContract");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        token = new DMDToken(mintDistributor, vestingContract);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(token.name(), "DMD Protocol");
        assertEq(token.symbol(), "DMD");
        assertEq(token.decimals(), 18);
        assertEq(token.MAX_SUPPLY(), 18_000_000e18);
        assertEq(token.MINT_DISTRIBUTOR(), mintDistributor);
        assertEq(token.VESTING_CONTRACT(), vestingContract);
        assertEq(token.totalMinted(), 0);
        assertEq(token.totalBurned(), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_Constructor_RevertsOnZeroMintDistributor() public {
        vm.expectRevert(DMDToken.InvalidRecipient.selector);
        new DMDToken(address(0), vestingContract);
    }

    function test_Constructor_RevertsOnZeroVestingContract() public {
        vm.expectRevert(DMDToken.InvalidRecipient.selector);
        new DMDToken(mintDistributor, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        uint256 amount = 1000e18;

        vm.prank(mintDistributor);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, amount);
        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalMinted(), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_FromVestingContract() public {
        uint256 amount = 1000e18;

        vm.prank(vestingContract);
        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalMinted(), amount);
    }

    function test_Mint_RevertsOnUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(DMDToken.Unauthorized.selector);
        token.mint(alice, 1000e18);
    }

    function test_Mint_RevertsOnZeroAddress() public {
        vm.prank(mintDistributor);
        vm.expectRevert(DMDToken.InvalidRecipient.selector);
        token.mint(address(0), 1000e18);
    }

    function test_Mint_RevertsOnZeroAmount() public {
        vm.prank(mintDistributor);
        vm.expectRevert(DMDToken.InvalidAmount.selector);
        token.mint(alice, 0);
    }

    function test_Mint_RevertsOnMaxSupplyExceeded() public {
        vm.startPrank(mintDistributor);
        token.mint(alice, token.MAX_SUPPLY());

        vm.expectRevert(DMDToken.ExceedsMaxSupply.selector);
        token.mint(alice, 1);
        vm.stopPrank();
    }

    function test_Mint_MultipleRecipients() public {
        vm.startPrank(mintDistributor);
        token.mint(alice, 1000e18);
        token.mint(bob, 2000e18);
        token.mint(charlie, 3000e18);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.balanceOf(bob), 2000e18);
        assertEq(token.balanceOf(charlie), 3000e18);
        assertEq(token.totalMinted(), 6000e18);
        assertEq(token.totalSupply(), 6000e18);
    }

    /*//////////////////////////////////////////////////////////////
                          BURNING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Success() public {
        uint256 mintAmount = 1000e18;
        uint256 burnAmount = 400e18;

        vm.prank(mintDistributor);
        token.mint(alice, mintAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, address(0), burnAmount);
        token.burn(burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    function test_Burn_RevertsOnZeroAmount() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(DMDToken.InvalidAmount.selector);
        token.burn(0);
    }

    function test_Burn_RevertsOnInsufficientBalance() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(DMDToken.InsufficientBalance.selector);
        token.burn(1001e18);
    }

    function test_Burn_FullBalance() public {
        uint256 amount = 1000e18;

        vm.prank(mintDistributor);
        token.mint(alice, amount);

        vm.prank(alice);
        token.burn(amount);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalBurned(), amount);
        assertEq(token.totalSupply(), 0);
    }

    function test_Burn_MultipleBurns() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.startPrank(alice);
        token.burn(200e18);
        token.burn(300e18);
        token.burn(100e18);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 400e18);
        assertEq(token.totalBurned(), 600e18);
        assertEq(token.totalSupply(), 400e18);
    }

    /*//////////////////////////////////////////////////////////////
                          SUPPLY TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SupplyTracking_MintAndBurn() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        assertEq(token.totalMinted(), 1000e18);
        assertEq(token.totalBurned(), 0);
        assertEq(token.totalSupply(), 1000e18);

        vm.prank(alice);
        token.burn(300e18);

        assertEq(token.totalMinted(), 1000e18); // Unchanged
        assertEq(token.totalBurned(), 300e18);
        assertEq(token.totalSupply(), 700e18);
    }

    function test_SupplyTracking_MultipleMintsBurns() public {
        vm.startPrank(mintDistributor);
        token.mint(alice, 500e18);
        token.mint(bob, 800e18);
        vm.stopPrank();

        vm.prank(alice);
        token.burn(200e18);

        assertEq(token.totalMinted(), 1300e18);
        assertEq(token.totalBurned(), 200e18);
        assertEq(token.totalSupply(), 1100e18);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer_Success() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 400e18);
        bool success = token.transfer(bob, 400e18);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.balanceOf(bob), 400e18);
    }

    function test_Transfer_RevertsOnInsufficientBalance() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(DMDToken.InsufficientBalance.selector);
        token.transfer(bob, 1001e18);
    }

    function test_Transfer_RevertsOnZeroAddress() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(DMDToken.InvalidRecipient.selector);
        token.transfer(address(0), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 APPROVAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_Success() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, 500e18);
        bool success = token.approve(bob, 500e18);

        assertTrue(success);
        assertEq(token.allowance(alice, bob), 500e18);
    }

    function test_Approve_Overwrite() public {
        vm.startPrank(alice);
        token.approve(bob, 500e18);
        token.approve(bob, 1000e18);
        vm.stopPrank();

        assertEq(token.allowance(alice, bob), 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferFrom_Success() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 500e18);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, charlie, 300e18);
        bool success = token.transferFrom(alice, charlie, 300e18);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(charlie), 300e18);
        assertEq(token.allowance(alice, bob), 200e18);
    }

    function test_TransferFrom_InfiniteApproval() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, charlie, 300e18);

        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_TransferFrom_RevertsOnInsufficientAllowance() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 500e18);

        vm.prank(bob);
        vm.expectRevert(DMDToken.InsufficientBalance.selector);
        token.transferFrom(alice, charlie, 501e18);
    }

    function test_TransferFrom_RevertsOnInsufficientBalance() public {
        vm.prank(mintDistributor);
        token.mint(alice, 500e18);

        vm.prank(alice);
        token.approve(bob, 1000e18);

        vm.prank(bob);
        vm.expectRevert(DMDToken.InsufficientBalance.selector);
        token.transferFrom(alice, charlie, 600e18);
    }

    function test_TransferFrom_RevertsOnZeroAddress() public {
        vm.prank(mintDistributor);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 500e18);

        vm.prank(bob);
        vm.expectRevert(DMDToken.InvalidRecipient.selector);
        token.transferFrom(alice, address(0), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, token.MAX_SUPPLY());

        vm.prank(mintDistributor);
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalMinted(), amount);
    }

    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, token.MAX_SUPPLY());
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(mintDistributor);
        token.mint(alice, mintAmount);

        vm.prank(alice);
        token.burn(burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    function testFuzz_Transfer(uint256 mintAmount, uint256 transferAmount) public {
        mintAmount = bound(mintAmount, 1, token.MAX_SUPPLY());
        transferAmount = bound(transferAmount, 0, mintAmount);

        vm.prank(mintDistributor);
        token.mint(alice, mintAmount);

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.balanceOf(alice), mintAmount - transferAmount);
        assertEq(token.balanceOf(bob), transferAmount);
    }
}
