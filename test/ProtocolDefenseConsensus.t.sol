// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ProtocolDefenseConsensus} from "../src/ProtocolDefenseConsensus.sol";
import {DMDToken} from "../src/DMDToken.sol";

contract MockMintDistributor {
    DMDToken public token;

    constructor(address _token) {
        token = DMDToken(_token);
    }

    function mint(address to, uint256 amount) external {
        token.mint(to, amount);
    }
}

contract ProtocolDefenseConsensusTest is Test {
    ProtocolDefenseConsensus public pdc;
    DMDToken public token;
    MockMintDistributor public distributor;

    address public alice;
    address public bob;
    address public charlie;
    address public testAdapter;
    address public initialAdapter;

    uint256 constant THREE_YEARS = 3 * 365 days;
    uint256 constant MAX_SUPPLY = 18_000_000e18;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        testAdapter = makeAddr("testAdapter");
        initialAdapter = makeAddr("tBTC");  // Initial adapter (pre-approved)

        // Deploy with computed addresses
        address expectedDistributor = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        address expectedVesting = makeAddr("vesting");

        token = new DMDToken(expectedDistributor, expectedVesting);
        distributor = new MockMintDistributor(address(token));

        // Deploy PDC with initial adapter pre-approved
        address[] memory initialAdapters = new address[](1);
        initialAdapters[0] = initialAdapter;
        pdc = new ProtocolDefenseConsensus(address(token), initialAdapters);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Constructor() public view {
        assertEq(address(pdc.DMD_TOKEN()), address(token));
        assertEq(pdc.GENESIS_TIME(), block.timestamp);
        assertFalse(pdc.activated());
        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.IDLE));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        address[] memory empty = new address[](0);
        vm.expectRevert(ProtocolDefenseConsensus.InvalidAdapter.selector);
        new ProtocolDefenseConsensus(address(0), empty);
    }

    function test_Constructor_PreApprovesInitialAdapters() public view {
        // Initial adapter should be pre-approved and active
        assertTrue(pdc.approvedAdapters(initialAdapter));
        assertTrue(pdc.isAdapterActive(initialAdapter));
        assertFalse(pdc.pausedAdapters(initialAdapter));
        assertFalse(pdc.deprecatedAdapters(initialAdapter));
    }

    function test_Constants() public view {
        assertEq(pdc.ACTIVATION_DELAY(), THREE_YEARS);
        assertEq(pdc.MIN_CIRCULATING_PERCENT(), 30);
        assertEq(pdc.MIN_UNIQUE_HOLDERS(), 10_000);
        assertEq(pdc.QUORUM_PERCENT(), 60);
        assertEq(pdc.APPROVAL_PERCENT(), 75);
        assertEq(pdc.VOTING_PERIOD(), 14 days);
        assertEq(pdc.EXECUTION_DELAY(), 7 days);
        assertEq(pdc.EXECUTION_WINDOW(), 30 days);
        assertEq(pdc.COOLDOWN_PERIOD(), 30 days);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACTIVATION TESTS - PDC MUST BE INERT BEFORE ACTIVATION
    // ═══════════════════════════════════════════════════════════════════════

    function test_CannotActivate_BeforeThreeYears() public {
        // Mint 30% supply to 10,000 holders
        _setupHoldersAndSupply();

        // Still before 3 years
        assertFalse(pdc.canActivate());

        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.activate();
    }

    function test_CannotActivate_WithoutSufficientSupply() public {
        // Warp past 3 years
        vm.warp(block.timestamp + THREE_YEARS + 1);

        // Only mint a small amount to few holders
        distributor.mint(alice, 1000e18);

        assertFalse(pdc.canActivate());

        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.activate();
    }

    function test_CannotActivate_WithoutSufficientHolders() public {
        // Warp past 3 years
        vm.warp(block.timestamp + THREE_YEARS + 1);

        // Mint 30% supply to only 1 holder
        uint256 thirtyPercent = (MAX_SUPPLY * 30) / 100;
        distributor.mint(alice, thirtyPercent);

        assertFalse(pdc.canActivate());

        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.activate();
    }

    function test_Activate_WhenAllConditionsMet() public {
        // Setup conditions
        vm.warp(block.timestamp + THREE_YEARS + 1);
        _setupHoldersAndSupply();

        assertTrue(pdc.canActivate());

        pdc.activate();

        assertTrue(pdc.activated());
    }

    function test_Activate_IsIrreversible() public {
        vm.warp(block.timestamp + THREE_YEARS + 1);
        _setupHoldersAndSupply();

        pdc.activate();
        assertTrue(pdc.activated());

        // Cannot activate again
        vm.expectRevert(ProtocolDefenseConsensus.PDCAlreadyActive.selector);
        pdc.activate();
    }

    function test_GetActivationStatus() public {
        (
            bool isActivated,
            bool timeConditionMet,
            bool supplyConditionMet,
            bool holderConditionMet,
            uint256 timeRemaining,
            uint256 currentCirculatingPercent,
            uint256 currentHolders
        ) = pdc.getActivationStatus();

        assertFalse(isActivated);
        assertFalse(timeConditionMet);
        assertFalse(supplyConditionMet);
        assertFalse(holderConditionMet);
        assertGt(timeRemaining, 0);
        assertEq(currentCirculatingPercent, 0);
        assertEq(currentHolders, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PDC INERTNESS TESTS - ALL FUNCTIONS MUST REVERT BEFORE ACTIVATION
    // ═══════════════════════════════════════════════════════════════════════

    function test_Propose_RevertsBeforeActivation() public {
        distributor.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, testAdapter);
    }

    function test_Vote_RevertsBeforeActivation() public {
        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.vote(true);
    }

    function test_FinalizeVoting_RevertsBeforeActivation() public {
        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.finalizeVoting();
    }

    function test_Execute_RevertsBeforeActivation() public {
        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.execute();
    }

    function test_EndCooldown_RevertsBeforeActivation() public {
        vm.expectRevert(ProtocolDefenseConsensus.PDCNotActive.selector);
        pdc.endCooldown();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Propose_RequiresVotingPower() public {
        _activatePDC();

        vm.prank(alice); // alice has no tokens
        vm.expectRevert(ProtocolDefenseConsensus.ZeroVotingPower.selector);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, testAdapter);
    }

    function test_Propose_CreatesProposal() public {
        _activatePDC();
        distributor.mint(alice, 1000e18);

        vm.prank(alice);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, testAdapter);

        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.VOTING));
        assertEq(pdc.proposalCount(), 1);
    }

    function test_Propose_OnlyOneAtATime() public {
        _activatePDC();
        distributor.mint(alice, 1000e18);
        distributor.mint(bob, 1000e18);

        vm.prank(alice);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, testAdapter);

        vm.prank(bob);
        vm.expectRevert(ProtocolDefenseConsensus.InvalidState.selector);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, makeAddr("adapter2"));
    }

    function test_Propose_ValidatesAction_CannotPauseUnapproved() public {
        _activatePDC();
        distributor.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert(ProtocolDefenseConsensus.InvalidAction.selector);
        pdc.propose(ProtocolDefenseConsensus.ActionType.PAUSE_ADAPTER, testAdapter);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Vote_RequiresVotingPower() public {
        _activatePDC();
        _createProposal();

        vm.prank(charlie); // charlie has no tokens
        vm.expectRevert(ProtocolDefenseConsensus.ZeroVotingPower.selector);
        pdc.vote(true);
    }

    function test_Vote_CannotVoteTwice() public {
        _activatePDC();
        _createProposal();

        distributor.mint(alice, 1000e18);

        vm.prank(alice);
        pdc.vote(true);

        vm.prank(alice);
        vm.expectRevert(ProtocolDefenseConsensus.AlreadyVoted.selector);
        pdc.vote(true);
    }

    function test_Vote_CannotVoteAfterPeriodEnds() public {
        _activatePDC();
        _createProposal();

        distributor.mint(alice, 1000e18);

        vm.warp(block.timestamp + 14 days + 1);

        vm.prank(alice);
        vm.expectRevert(ProtocolDefenseConsensus.VotingEnded.selector);
        pdc.vote(true);
    }

    function test_Vote_RecordsVotes() public {
        _activatePDC();
        _createProposal();

        // Note: bob already has 1000e18 from _createProposal()
        distributor.mint(alice, 1000e18);
        distributor.mint(bob, 2000e18); // bob now has 3000e18 total

        vm.prank(alice);
        pdc.vote(true);

        vm.prank(bob);
        pdc.vote(false);

        (,,,,,,, uint256 yesVotes, uint256 noVotes,,,) = pdc.getProposal();
        assertEq(yesVotes, 1000e18);
        assertEq(noVotes, 3000e18); // bob has 1000 + 2000 = 3000
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FINALIZE VOTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_FinalizeVoting_CannotFinalizeEarly() public {
        _activatePDC();
        _createProposal();

        vm.expectRevert(ProtocolDefenseConsensus.VotingNotEnded.selector);
        pdc.finalizeVoting();
    }

    function test_FinalizeVoting_FailsWithoutQuorum() public {
        _activatePDC();
        _createProposal();

        // Only 10% of supply votes (need 60%)
        uint256 tenPercent = (MAX_SUPPLY * 10) / 100;
        distributor.mint(alice, tenPercent);

        vm.prank(alice);
        pdc.vote(true);

        vm.warp(block.timestamp + 14 days + 1);

        pdc.finalizeVoting();

        // Should return to IDLE (proposal failed)
        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.IDLE));
    }

    function test_FinalizeVoting_FailsWithoutApproval() public {
        _activatePDC();
        _createProposal();

        // 50% of supply votes, but only 50% say yes (need 75%)
        uint256 quarterSupply = (MAX_SUPPLY * 25) / 100;
        distributor.mint(alice, quarterSupply);
        distributor.mint(bob, quarterSupply);

        vm.prank(alice);
        pdc.vote(true);

        vm.prank(bob);
        pdc.vote(false);

        vm.warp(block.timestamp + 14 days + 1);

        pdc.finalizeVoting();

        // Should return to IDLE (proposal failed)
        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.IDLE));
    }

    function test_FinalizeVoting_PassesWithQuorumAndApproval() public {
        _activatePDC();
        _createProposal();

        // 50% of supply votes, 80% say yes
        uint256 fortyPercent = (MAX_SUPPLY * 40) / 100;
        uint256 tenPercent = (MAX_SUPPLY * 10) / 100;
        distributor.mint(alice, fortyPercent);
        distributor.mint(bob, tenPercent);

        vm.prank(alice);
        pdc.vote(true);

        vm.prank(bob);
        pdc.vote(false);

        vm.warp(block.timestamp + 14 days + 1);

        pdc.finalizeVoting();

        // Should be QUEUED
        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.QUEUED));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Execute_CannotExecuteEarly() public {
        _activatePDC();
        _passProposal();

        vm.expectRevert(ProtocolDefenseConsensus.ExecutionDelayNotMet.selector);
        pdc.execute();
    }

    function test_Execute_ApprovesAdapter() public {
        _activatePDC();
        _passProposal();

        vm.warp(block.timestamp + 7 days + 1);

        pdc.execute();

        assertTrue(pdc.approvedAdapters(testAdapter));
        assertTrue(pdc.isAdapterActive(testAdapter));
        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.COOLDOWN));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COOLDOWN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_EndCooldown_CannotEndEarly() public {
        _activatePDC();
        _passProposal();

        vm.warp(block.timestamp + 7 days + 1);
        pdc.execute();

        vm.expectRevert(ProtocolDefenseConsensus.CooldownNotComplete.selector);
        pdc.endCooldown();
    }

    function test_EndCooldown_ReturnsToIdle() public {
        _activatePDC();
        _passProposal();

        vm.warp(block.timestamp + 7 days + 1);
        pdc.execute();

        vm.warp(block.timestamp + 30 days + 1);
        pdc.endCooldown();

        assertEq(uint256(pdc.proposalState()), uint256(ProtocolDefenseConsensus.ProposalState.IDLE));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADAPTER STATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_AdapterLifecycle() public {
        _activatePDC();

        // 1. Approve adapter
        _passProposal();
        vm.warp(block.timestamp + 7 days + 1);
        pdc.execute();
        assertTrue(pdc.isAdapterActive(testAdapter));

        // 2. Wait for cooldown
        vm.warp(block.timestamp + 30 days + 1);
        pdc.endCooldown();

        // 3. Pause adapter - alice already has 60% from _passProposal()
        // She can propose and vote with her existing balance
        vm.prank(alice);
        pdc.propose(ProtocolDefenseConsensus.ActionType.PAUSE_ADAPTER, testAdapter);

        vm.prank(alice);
        pdc.vote(true);

        vm.warp(block.timestamp + 14 days + 1);
        pdc.finalizeVoting();

        vm.warp(block.timestamp + 7 days + 1);
        pdc.execute();

        assertTrue(pdc.pausedAdapters(testAdapter));
        assertFalse(pdc.isAdapterActive(testAdapter));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _setupHoldersAndSupply() internal {
        // Mint 31% of supply across 10,000+ holders (slightly over 30% to ensure threshold is met)
        uint256 thirtyOnePercent = (MAX_SUPPLY * 31) / 100;
        uint256 perHolder = thirtyOnePercent / 10_001;

        for (uint256 i = 0; i < 10_001; i++) {
            address holder = address(uint160(0x1000 + i));
            distributor.mint(holder, perHolder);
        }
    }

    function _activatePDC() internal {
        vm.warp(block.timestamp + THREE_YEARS + 1);
        _setupHoldersAndSupply();
        pdc.activate();
    }

    function _createProposal() internal {
        // Give proposer some tokens
        distributor.mint(bob, 1000e18);

        vm.prank(bob);
        pdc.propose(ProtocolDefenseConsensus.ActionType.APPROVE_ADAPTER, testAdapter);
    }

    function _passProposal() internal {
        _createProposal();

        // Get enough votes to pass (60% quorum, 75% approval)
        // Need 60% to vote, with 75% YES = 45% YES minimum
        // We'll give alice 60% and she votes YES
        uint256 sixtyPercent = (MAX_SUPPLY * 60) / 100;
        distributor.mint(alice, sixtyPercent);

        vm.prank(alice);
        pdc.vote(true);

        vm.warp(block.timestamp + 14 days + 1);
        pdc.finalizeVoting();
    }
}
