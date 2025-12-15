// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/DMDToken.sol";
import "../src/BTCReserveVault.sol";
import "../src/BTCAssetRegistry.sol";
import "../src/EmissionScheduler.sol";
import "../src/MintDistributor.sol";
import "../src/RedemptionEngine.sol";
import "../src/VestingContract.sol";
import "../src/interfaces/IDMDToken.sol";
import "../src/interfaces/IBTCReserveVault.sol";
import "../src/interfaces/IEmissionScheduler.sol";

contract MockWBTC {
    string public constant name = "Wrapped Bitcoin";
    string public constant symbol = "WBTC";
    uint8 public constant decimals = 8;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract DeployDMDFresh is Script {
    // Store deployed contracts as state variables
    MockWBTC public wbtc;
    BTCAssetRegistry public assetRegistry;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _printHeader(deployer);

        vm.startBroadcast(deployerPrivateKey);

        _deployMockWBTC();
        _deployProtocol(deployer);
        _initializeSystem();
        _mintTestTokens(deployer);

        vm.stopBroadcast();

        _saveDeployment(deployer);
        _printSummary();
    }

    function _printHeader(address deployer) internal view {
        console.log("=====================================");
        console.log("DMD PROTOCOL - FRESH DEPLOYMENT");
        console.log("Multi-Asset BTC Support Enabled");
        console.log("=====================================");
        console.log("Network: Base Sepolia");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        require(deployer.balance >= 0.05 ether, "Need at least 0.05 ETH");
    }

    function _deployMockWBTC() internal {
        console.log("Step 1: Deploying MockWBTC...");
        wbtc = new MockWBTC();
        console.log("  MockWBTC:", address(wbtc));
        console.log("");
    }

    function _deployProtocol(address deployer) internal {
        console.log("Step 2: Deploying protocol contracts...");

        uint256 nonce = vm.getNonce(deployer);
        address pAssetRegistry = vm.computeCreateAddress(deployer, nonce);
        address pVault = vm.computeCreateAddress(deployer, nonce + 1);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 2);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 3);
        address pToken = vm.computeCreateAddress(deployer, nonce + 4);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 5);

        // Deploy BTCAssetRegistry
        assetRegistry = new BTCAssetRegistry();
        console.log("  [1/7] AssetRegistry:", address(assetRegistry));

        // Deploy Vault with asset registry
        vault = new BTCReserveVault(pAssetRegistry, pRedemption);
        console.log("  [2/7] Vault:", address(vault));

        scheduler = new EmissionScheduler(deployer, pDistributor);
        console.log("  [3/7] Scheduler:", address(scheduler));

        distributor = new MintDistributor(
            deployer,
            IDMDToken(pToken),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
        console.log("  [4/7] Distributor:", address(distributor));

        dmdToken = new DMDToken(address(distributor));
        console.log("  [5/7] DMDToken:", address(dmdToken));

        redemption = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );
        console.log("  [6/7] Redemption:", address(redemption));

        vesting = new VestingContract(deployer, IDMDToken(address(dmdToken)));
        console.log("  [7/7] Vesting:", address(vesting));

        require(address(assetRegistry) == pAssetRegistry, "AssetRegistry mismatch");
        require(address(vault) == pVault, "Vault mismatch");
        require(address(scheduler) == pScheduler, "Scheduler mismatch");
        require(address(distributor) == pDistributor, "Distributor mismatch");
        require(address(dmdToken) == pToken, "Token mismatch");
        require(address(redemption) == pRedemption, "Redemption mismatch");

        console.log("  All addresses verified!");
        console.log("");
    }

    function _initializeSystem() internal {
        console.log("Step 3: Initializing system...");

        // Add WBTC as approved asset
        assetRegistry.addBTCAsset(address(wbtc), false, "WBTC");
        console.log("  WBTC added to asset registry");

        scheduler.startEmissions();
        console.log("  Emissions started");

        distributor.startDistribution();
        console.log("  Distribution started");
        console.log("");
    }

    function _mintTestTokens(address deployer) internal {
        console.log("Step 4: Minting test WBTC...");
        wbtc.mint(deployer, 100 * 1e8);
        console.log("  Minted 100 WBTC");
        console.log("");
    }

    function _saveDeployment(address deployer) internal {
        console.log("Step 5: Saving deployment...");

        string memory info = string.concat(
            "# DMD Protocol Deployment - Multi-Asset\n",
            "WBTC=", vm.toString(address(wbtc)), "\n",
            "ASSET_REGISTRY=", vm.toString(address(assetRegistry)), "\n",
            "DMD_TOKEN=", vm.toString(address(dmdToken)), "\n",
            "VAULT=", vm.toString(address(vault)), "\n",
            "SCHEDULER=", vm.toString(address(scheduler)), "\n",
            "DISTRIBUTOR=", vm.toString(address(distributor)), "\n",
            "REDEMPTION=", vm.toString(address(redemption)), "\n",
            "VESTING=", vm.toString(address(vesting)), "\n"
        );

        vm.writeFile("deployments/testnet-deployment.env", info);
        console.log("  Saved to deployments/testnet-deployment.env");
        console.log("");
    }

    function _printSummary() internal view {
        console.log("=====================================");
        console.log("DEPLOYMENT SUCCESSFUL!");
        console.log("=====================================");
        console.log("");
        console.log("WBTC:          ", address(wbtc));
        console.log("AssetRegistry: ", address(assetRegistry));
        console.log("DMDToken:      ", address(dmdToken));
        console.log("Vault:         ", address(vault));
        console.log("Scheduler:     ", address(scheduler));
        console.log("Distributor:   ", address(distributor));
        console.log("Redemption:    ", address(redemption));
        console.log("Vesting:       ", address(vesting));
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on Basescan");
        console.log("2. Test WBTC locking: vault.lock(WBTC, amount, months)");
        console.log("3. Add more BTC assets: assetRegistry.addBTCAsset()");
        console.log("");
    }
}
