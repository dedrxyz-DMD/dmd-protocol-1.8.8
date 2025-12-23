// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/DMDToken.sol";
import "../src/BTCReserveVault.sol";
import "../src/EmissionScheduler.sol";
import "../src/MintDistributor.sol";
import "../src/RedemptionEngine.sol";
import "../src/VestingContract.sol";
import "../src/interfaces/IDMDToken.sol";
import "../src/interfaces/IBTCReserveVault.sol";
import "../src/interfaces/IEmissionScheduler.sol";
import "../src/interfaces/IMintDistributor.sol";

/// @title DeployMainnet - DMD Protocol v1.8.8 Base Mainnet Deployment
/// @dev tBTC-only, fully decentralized, no admin
contract DeployMainnet is Script {
    // Base Mainnet tBTC (Threshold Network)
    address constant TBTC = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b;

    /*//////////////////////////////////////////////////////////////
                        TEAM ALLOCATION CONFIG
    //////////////////////////////////////////////////////////////*/

    // Total team allocation: 3,600,000 DMD (20% of 18M max supply)
    //
    // Distribution:
    // - Foundation:    1,440,000 DMD (40% of team allocation)
    // - Founders:      1,080,000 DMD (30% of team allocation)
    // - Developers:      720,000 DMD (20% of team allocation)
    // - Contributors:    360,000 DMD (10% of team allocation)
    //
    // Vesting schedule for ALL beneficiaries:
    // - TGE (Day 0):  5% unlocked immediately
    // - Linear:       95% over 7 years

    // Team wallet addresses (MAINNET - DO NOT CHANGE)
    address constant FOUNDATION   = 0x7c507141B182b337BEC960bAE0F53ED80b54D68a;
    address constant FOUNDERS     = 0x3137e2508A9407143243887DFf3707C4A91077F2;
    address constant DEVELOPERS   = 0x1a7Cf64e6026d0b4ac7e113dEaA686D14c81D29C;
    address constant CONTRIBUTORS = 0xB03414CF7e2904f4e304e825D780dfE93a910B6C;

    /*//////////////////////////////////////////////////////////////
                              CONTRACTS
    //////////////////////////////////////////////////////////////*/

    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // ============================================================
        // TEAM WALLET CONFIGURATION (MAINNET)
        // ============================================================

        address[] memory beneficiaries = new address[](4);
        uint256[] memory allocations = new uint256[](4);

        // Foundation (40% of team = 1,440,000 DMD)
        beneficiaries[0] = FOUNDATION;
        allocations[0] = 1_440_000e18;

        // Founders (30% of team = 1,080,000 DMD)
        beneficiaries[1] = FOUNDERS;
        allocations[1] = 1_080_000e18;

        // Developers (20% of team = 720,000 DMD)
        beneficiaries[2] = DEVELOPERS;
        allocations[2] = 720_000e18;

        // Contributors (10% of team = 360,000 DMD)
        beneficiaries[3] = CONTRIBUTORS;
        allocations[3] = 360_000e18;

        // ============================================================
        // END CONFIGURATION - Total: 3,600,000 DMD
        // ============================================================

        // Validate total allocation
        uint256 totalAlloc = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAlloc += allocations[i];
        }
        require(totalAlloc == 3_600_000e18, "Total allocation must be 3.6M DMD");

        console.log("==============================================");
        console.log("DMD Protocol v1.8.8 - Base Mainnet Deployment");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("tBTC:", TBTC);
        console.log("");

        require(deployer.balance >= 0.005 ether, "Need at least 0.005 ETH for gas");

        vm.startBroadcast(pk);

        // Compute addresses for circular dependencies
        // Order: Vault, Scheduler, Distributor, Token, Redemption, Vesting
        uint256 nonce = vm.getNonce(deployer);
        address pVault = vm.computeCreateAddress(deployer, nonce);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 1);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 2);
        address pToken = vm.computeCreateAddress(deployer, nonce + 3);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 4);
        address pVesting = vm.computeCreateAddress(deployer, nonce + 5);

        console.log("Deploying contracts...");
        console.log("");

        // 1. Deploy BTCReserveVault
        vault = new BTCReserveVault(TBTC, pRedemption);
        require(address(vault) == pVault, "Vault address mismatch");
        console.log("1. BTCReserveVault:", address(vault));

        // 2. Deploy EmissionScheduler
        scheduler = new EmissionScheduler(pDistributor);
        require(address(scheduler) == pScheduler, "Scheduler address mismatch");
        console.log("2. EmissionScheduler:", address(scheduler));

        // 3. Deploy MintDistributor
        distributor = new MintDistributor(
            IDMDToken(pToken),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
        require(address(distributor) == pDistributor, "Distributor address mismatch");
        console.log("3. MintDistributor:", address(distributor));

        // 4. Deploy DMDToken (dual minter: distributor + vesting)
        dmdToken = new DMDToken(address(distributor), pVesting);
        require(address(dmdToken) == pToken, "Token address mismatch");
        console.log("4. DMDToken:", address(dmdToken));

        // 5. Deploy RedemptionEngine
        redemption = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault)),
            IMintDistributor(address(distributor))
        );
        require(address(redemption) == pRedemption, "Redemption address mismatch");
        console.log("5. RedemptionEngine:", address(redemption));

        // 6. Deploy VestingContract (team allocation: 3.6M DMD = 20% of max)
        vesting = new VestingContract(IDMDToken(address(dmdToken)), beneficiaries, allocations);
        require(address(vesting) == pVesting, "Vesting address mismatch");
        console.log("6. VestingContract:", address(vesting));

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("==============================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("==============================================");
        console.log("");
        console.log("Contract Addresses:");
        console.log("-------------------");
        console.log("tBTC (external):    ", TBTC);
        console.log("BTCReserveVault:    ", address(vault));
        console.log("EmissionScheduler:  ", address(scheduler));
        console.log("MintDistributor:    ", address(distributor));
        console.log("DMDToken:           ", address(dmdToken));
        console.log("RedemptionEngine:   ", address(redemption));
        console.log("VestingContract:    ", address(vesting));
        console.log("");
        console.log("Token Economics:");
        console.log("----------------");
        console.log("Max Supply:         18,000,000 DMD");
        console.log("Emission Cap:       14,400,000 DMD (80%)");
        console.log("Team Allocation:    3,600,000 DMD (20%)");
        console.log("Year 1 Emission:    3,600,000 DMD");
        console.log("Annual Decay:       25%");
        console.log("");
        console.log("Team Vesting Beneficiaries:");
        console.log("---------------------------");
        console.log("1. Foundation:   ", FOUNDATION);
        console.log("   Allocation:    1,440,000 DMD (40%)");
        console.log("   TGE (5%):      72,000 DMD");
        console.log("");
        console.log("2. Founders:     ", FOUNDERS);
        console.log("   Allocation:    1,080,000 DMD (30%)");
        console.log("   TGE (5%):      54,000 DMD");
        console.log("");
        console.log("3. Developers:   ", DEVELOPERS);
        console.log("   Allocation:    720,000 DMD (20%)");
        console.log("   TGE (5%):      36,000 DMD");
        console.log("");
        console.log("4. Contributors: ", CONTRIBUTORS);
        console.log("   Allocation:    360,000 DMD (10%)");
        console.log("   TGE (5%):      18,000 DMD");
        console.log("");
        console.log("==============================================");
        console.log("NEXT STEPS:");
        console.log("==============================================");
        console.log("1. Verify all contracts on BaseScan");
        console.log("2. Wait 7 days for first epoch");
        console.log("3. Call finalizeEpoch() to start emissions");
        console.log("4. Team can claim TGE immediately via vesting.claim()");
        console.log("");
        console.log("IMPORTANT: Save these addresses!");
    }
}
