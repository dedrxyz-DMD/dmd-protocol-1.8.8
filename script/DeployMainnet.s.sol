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

    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

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
        address[] memory beneficiaries = new address[](1);
        uint256[] memory allocations = new uint256[](1);
        beneficiaries[0] = deployer;
        allocations[0] = 3_600_000e18; // 3.6M DMD

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
        console.log("Verify contracts on BaseScan:");
        console.log("------------------------------");
        console.log("forge verify-contract", address(vault), "src/BTCReserveVault.sol:BTCReserveVault --chain base");
    }
}
