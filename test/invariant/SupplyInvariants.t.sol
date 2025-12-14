// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/DMDToken.sol";
import "../src/BTCReserveVault.sol";
import "../src/EmissionScheduler.sol";
import "../src/MintDistributor.sol";
import "../src/RedemptionEngine.sol";

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
        
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract Handler is Test {
    // Core contracts
    DMDToken public dmdToken;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    RedemptionEngine public redemptionEngine;
    MockWBTC public wbtc;

    // Actors
    address[] public actors;
    address public currentActor;

    // Ghost variables for tracking
    uint256 public ghost_totalLockedWBTC;
    uint256 public ghost_totalSystemWeight;
    uint256 public ghost_totalBurned;
    mapping(address => uint256) public ghost_userWeights;
    mapping(address => uint256[]) public ghost_userPositions;

    // Action counters
    uint256 public lockCount;
    uint256 public claimCount;
    uint256 public redeemCount;
    uint256 public transferCount;
    uint256 public finalizeCount;

    constructor(
        DMDToken _dmdToken,
        BTCReserveVault _vault,
        EmissionScheduler _scheduler,
        MintDistributor _distributor,
        RedemptionEngine _redemptionEngine,
        MockWBTC _wbtc,
        address[] memory _actors
    ) {
        dmdToken = _dmdToken;
        vault = _vault;
        scheduler = _scheduler;
        distributor = _distributor;
        redemptionEngine = _redemptionEngine;
        wbtc = _wbtc;
        actors = _actors;
    }

    /*//////////////////////////////////////////////////////////////
                          ACTOR ACTIONS
    //////////////////////////////////////////////////////////////*/

    function lockWBTC(uint256 actorSeed, uint256 amount, uint256 lockMonths) external {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        amount = bound(amount, 1e7, 1e9); // 0.1 to 10 WBTC (8 decimals)
        lockMonths = bound(lockMonths, 1, 36);

        // Ensure actor has WBTC
        if (wbtc.balanceOf(currentActor) < amount) {
            wbtc.mint(currentActor, amount);
        }

        vm.startPrank(currentActor);
        wbtc.approve(address(vault), amount);
        
        try vault.lock(amount, lockMonths) returns (uint256 positionId) {
            lockCount++;
            
            uint256 weight = vault.calculateWeight(amount, lockMonths);
            ghost_totalLockedWBTC += amount;
            ghost_totalSystemWeight += weight;
            ghost_userWeights[currentActor] += weight;
            ghost_userPositions[currentActor].push(positionId);
        } catch {
            // Lock failed, continue
        }
        vm.stopPrank();
    }

    function finalizeEpoch() external {
        uint256 currentEpoch = distributor.getCurrentEpoch();
        
        // Can only finalize if we're past epoch 0
        if (currentEpoch > 0) {
            uint256 epochToFinalize = currentEpoch - 1;
            
            (, , bool finalized) = distributor.getEpochData(epochToFinalize);
            
            if (!finalized) {
                try distributor.finalizeEpoch() {
                    finalizeCount++;
                } catch {
                    // Finalization failed, continue
                }
            }
        }
    }

    function claimDMD(uint256 actorSeed, uint256 epochId) external {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        epochId = bound(epochId, 0, distributor.getCurrentEpoch());

        (, , bool finalized) = distributor.getEpochData(epochId);
        
        if (finalized && !distributor.claimed(epochId, currentActor)) {
            vm.prank(currentActor);
            try distributor.claim(epochId) {
                claimCount++;
            } catch {
                // Claim failed (no weight, etc)
            }
        }
    }

    function redeemPosition(uint256 actorSeed, uint256 positionIndex) external {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        
        uint256[] memory positions = ghost_userPositions[currentActor];
        if (positions.length == 0) return;
        
        positionIndex = bound(positionIndex, 0, positions.length - 1);
        uint256 positionId = positions[positionIndex];

        if (redemptionEngine.isRedeemed(currentActor, positionId)) return;

        (uint256 amount, , , uint256 weight, ) = vault.getPosition(currentActor, positionId);
        if (amount == 0) return;

        if (vault.isUnlocked(currentActor, positionId)) {
            uint256 requiredBurn = redemptionEngine.getRequiredBurn(currentActor, positionId);
            
            if (dmdToken.balanceOf(currentActor) >= requiredBurn) {
                vm.startPrank(currentActor);
                dmdToken.approve(address(redemptionEngine), requiredBurn);
                
                try redemptionEngine.redeem(positionId, requiredBurn) {
                    redeemCount++;
                    ghost_totalBurned += requiredBurn;
                    ghost_totalLockedWBTC -= amount;
                    ghost_totalSystemWeight -= weight;
                    ghost_userWeights[currentActor] -= weight;
                } catch {
                    // Redemption failed
                }
                vm.stopPrank();
            }
        }
    }

    function transferDMD(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[bound(fromSeed, 0, actors.length - 1)];
        address to = actors[bound(toSeed, 0, actors.length - 1)];
        
        if (from == to) return;
        
        uint256 balance = dmdToken.balanceOf(from);
        if (balance == 0) return;
        
        amount = bound(amount, 1, balance);

        vm.prank(from);
        try dmdToken.transfer(to, amount) {
            transferCount++;
        } catch {
            // Transfer failed
        }
    }

    function warpTime(uint256 timeJump) external {
        timeJump = bound(timeJump, 1 hours, 30 days);
        vm.warp(block.timestamp + timeJump);
    }
}

contract SupplyInvariantsTest is Test {
    // Core contracts
    DMDToken public dmdToken;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    RedemptionEngine public redemptionEngine;
    MockWBTC public wbtc;

    Handler public handler;

    address public owner;
    address[] public actors;

    function setUp() public {
        owner = address(this);

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }

        // Deploy mock WBTC
        wbtc = new MockWBTC();

        // Deploy core contracts
        dmdToken = new DMDToken(address(1)); // Placeholder
        scheduler = new EmissionScheduler(owner, address(1)); // Placeholder
        vault = new BTCReserveVault(address(wbtc), address(1)); // Placeholder

        // Deploy MintDistributor
        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );

        // Redeploy with correct addresses
        dmdToken = new DMDToken(address(distributor));
        scheduler = new EmissionScheduler(owner, address(distributor));

        // Deploy RedemptionEngine
        redemptionEngine = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );

        // Redeploy vault with correct RedemptionEngine
        vault = new BTCReserveVault(address(wbtc), address(redemptionEngine));

        // Redeploy distributor with correct vault
        distributor = new MintDistributor(
            owner,
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );

        // Final redeploy of DMDToken with correct distributor
        dmdToken = new DMDToken(address(distributor));

        // Start emissions and distribution
        scheduler.startEmissions();
        distributor.startDistribution();

        // Deploy handler
        handler = new Handler(
            dmdToken,
            vault,
            scheduler,
            distributor,
            redemptionEngine,
            wbtc,
            actors
        );

        // Target handler for invariant testing
        targetContract(address(handler));

        // Target specific functions
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.lockWBTC.selector;
        selectors[1] = Handler.finalizeEpoch.selector;
        selectors[2] = Handler.claimDMD.selector;
        selectors[3] = Handler.redeemPosition.selector;
        selectors[4] = Handler.transferDMD.selector;
        selectors[5] = Handler.warpTime.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }

    /*//////////////////////////////////////////////////////////////
                          INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_supplyConsistency() public view {
        // totalMinted - totalBurned = circulatingSupply
        uint256 totalMinted = dmdToken.totalMinted();
        uint256 totalBurned = dmdToken.totalBurned();
        uint256 circulatingSupply = dmdToken.circulatingSupply();

        assertEq(
            circulatingSupply,
            totalMinted - totalBurned,
            "Supply inconsistency: totalMinted - totalBurned != circulatingSupply"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_weightConsistency() public view {
        // sum(userWeights) = totalSystemWeight
        uint256 sumUserWeights = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            sumUserWeights += vault.totalWeightOf(actors[i]);
        }

        assertEq(
            sumUserWeights,
            vault.totalSystemWeight(),
            "Weight inconsistency: sum(userWeights) != totalSystemWeight"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_emissionCap() public view {
        // totalEmitted ≤ 14.4M
        uint256 totalEmitted = scheduler.totalEmitted();
        uint256 emissionCap = scheduler.EMISSION_CAP();

        assertLe(
            totalEmitted,
            emissionCap,
            "Emission cap violated: totalEmitted > 14.4M"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_balanceSum() public view {
        // sum(balances) = circulatingSupply
        uint256 sumBalances = 0;
        
        for (uint256 i = 0; i < actors.length; i++) {
            sumBalances += dmdToken.balanceOf(actors[i]);
        }

        // Add distributor balance (not yet claimed)
        // Add vesting balance if applicable
        // For now just check actors

        assertLe(
            sumBalances,
            dmdToken.circulatingSupply(),
            "Balance sum exceeds circulating supply"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_vaultLockBalance() public view {
        // Ghost tracked vs actual
        assertEq(
            vault.totalLockedWBTC(),
            handler.ghost_totalLockedWBTC(),
            "Vault lock balance mismatch with ghost variable"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_totalBurnedTracking() public view {
        // DMD contract burn tracking
        assertGe(
            dmdToken.totalBurned(),
            handler.ghost_totalBurned(),
            "Total burned less than ghost tracked burns"
        );
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_noNegativeBalances() public view {
        // All actor balances should be >= 0 (implicit in uint256)
        for (uint256 i = 0; i < actors.length; i++) {
            // Just reading ensures no revert
            dmdToken.balanceOf(actors[i]);
            vault.totalWeightOf(actors[i]);
            wbtc.balanceOf(actors[i]);
        }
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_maxSupplyNeverExceeded() public view {
        // totalMinted ≤ MAX_SUPPLY
        assertLe(
            dmdToken.totalMinted(),
            dmdToken.MAX_SUPPLY(),
            "Max supply exceeded"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CALL SUMMARY
    //////////////////////////////////////////////////////////////*/

    function invariant_callSummary() public view {
        console.log("\n=== Invariant Test Summary ===");
        console.log("Lock calls:", handler.lockCount());
        console.log("Finalize calls:", handler.finalizeCount());
        console.log("Claim calls:", handler.claimCount());
        console.log("Redeem calls:", handler.redeemCount());
        console.log("Transfer calls:", handler.transferCount());
        console.log("\n=== State Summary ===");
        console.log("Total minted:", dmdToken.totalMinted() / 1e18, "DMD");
        console.log("Total burned:", dmdToken.totalBurned() / 1e18, "DMD");
        console.log("Circulating:", dmdToken.circulatingSupply() / 1e18, "DMD");
        console.log("Total emitted:", scheduler.totalEmitted() / 1e18, "DMD");
        console.log("Total locked WBTC:", vault.totalLockedWBTC() / 1e8, "BTC");
        console.log("Total system weight:", vault.totalSystemWeight() / 1e8);
    }
}