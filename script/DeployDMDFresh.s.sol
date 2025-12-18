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

/**
 * @title MockTBTC
 * @notice Mock tBTC token for testnet deployment (18 decimals like real tBTC)
 */
contract MockTBTC {
    string public constant name = "tBTC v2";
    string public constant symbol = "tBTC";
    uint8 public constant decimals = 18;

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

/**
 * @title DeployDMDFresh
 * @notice Deployment script for DMD Protocol v1.8.8 - tBTC-only, fully decentralized
 * @dev Deploys to Base Sepolia testnet with MockTBTC for testing
 *
 * Architecture:
 * - tBTC-only (immutable address, no registry)
 * - No owner, no admin, no governance after deployment
 * - Flash loan protection: 7-day warmup + 3-day vesting
 * - 7-day epoch emissions, 18% annual decay, 14.4M cap
 */
contract DeployDMDFresh is Script {
    // Store deployed contracts as state variables
    MockTBTC public tbtc;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    // Real tBTC address on Base Mainnet
    address constant TBTC_BASE_MAINNET = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _printHeader(deployer);

        vm.startBroadcast(deployerPrivateKey);

        _deployMockTBTC();
        _deployProtocol(deployer);
        _initializeSystem();
        _mintTestTokens(deployer);

        vm.stopBroadcast();

        _saveDeployment(deployer);
        _printSummary();
    }

    /// @notice Deploy to mainnet using real tBTC address
    function runMainnet() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=====================================");
        console.log("DMD PROTOCOL v1.8.8 - MAINNET DEPLOY");
        console.log("tBTC-Only | No Owner | Immutable");
        console.log("=====================================");
        console.log("Network: Base Mainnet");
        console.log("Deployer:", deployer);
        console.log("tBTC Address:", TBTC_BASE_MAINNET);
        console.log("");

        require(deployer.balance >= 0.05 ether, "Need at least 0.05 ETH");

        vm.startBroadcast(deployerPrivateKey);

        _deployProtocolMainnet(deployer);
        _initializeSystem();

        vm.stopBroadcast();

        _saveMainnetDeployment(deployer);
        _printMainnetSummary();
    }

    function _printHeader(address deployer) internal view {
        console.log("=====================================");
        console.log("DMD PROTOCOL v1.8.8 - FRESH DEPLOYMENT");
        console.log("tBTC-Only | Flash Loan Protected");
        console.log("=====================================");
        console.log("Network: Base Sepolia (Testnet)");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        require(deployer.balance >= 0.05 ether, "Need at least 0.05 ETH");
    }

    function _deployMockTBTC() internal {
        console.log("Step 1: Deploying MockTBTC (18 decimals)...");
        tbtc = new MockTBTC();
        console.log("  MockTBTC:", address(tbtc));
        console.log("");
    }

    function _deployProtocol(address deployer) internal {
        console.log("Step 2: Deploying protocol contracts...");

        uint256 nonce = vm.getNonce(deployer);
        address pVault = vm.computeCreateAddress(deployer, nonce);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 1);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 2);
        address pToken = vm.computeCreateAddress(deployer, nonce + 3);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 4);

        // Deploy Vault with tBTC address (immutable)
        vault = new BTCReserveVault(address(tbtc), pRedemption);
        console.log("  [1/6] Vault:", address(vault));

        scheduler = new EmissionScheduler(deployer, pDistributor);
        console.log("  [2/6] Scheduler:", address(scheduler));

        distributor = new MintDistributor(
            deployer,
            IDMDToken(pToken),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
        console.log("  [3/6] Distributor:", address(distributor));

        dmdToken = new DMDToken(address(distributor));
        console.log("  [4/6] DMDToken:", address(dmdToken));

        redemption = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );
        console.log("  [5/6] Redemption:", address(redemption));

        vesting = new VestingContract(deployer, IDMDToken(address(dmdToken)));
        console.log("  [6/6] Vesting:", address(vesting));

        require(address(vault) == pVault, "Vault mismatch");
        require(address(scheduler) == pScheduler, "Scheduler mismatch");
        require(address(distributor) == pDistributor, "Distributor mismatch");
        require(address(dmdToken) == pToken, "Token mismatch");
        require(address(redemption) == pRedemption, "Redemption mismatch");

        console.log("  All addresses verified!");
        console.log("");
    }

    function _deployProtocolMainnet(address deployer) internal {
        console.log("Deploying protocol contracts to mainnet...");

        uint256 nonce = vm.getNonce(deployer);
        address pVault = vm.computeCreateAddress(deployer, nonce);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 1);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 2);
        address pToken = vm.computeCreateAddress(deployer, nonce + 3);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 4);

        // Deploy Vault with REAL tBTC address (immutable)
        vault = new BTCReserveVault(TBTC_BASE_MAINNET, pRedemption);
        console.log("  [1/6] Vault:", address(vault));

        scheduler = new EmissionScheduler(deployer, pDistributor);
        console.log("  [2/6] Scheduler:", address(scheduler));

        distributor = new MintDistributor(
            deployer,
            IDMDToken(pToken),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
        console.log("  [3/6] Distributor:", address(distributor));

        dmdToken = new DMDToken(address(distributor));
        console.log("  [4/6] DMDToken:", address(dmdToken));

        redemption = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );
        console.log("  [5/6] Redemption:", address(redemption));

        vesting = new VestingContract(deployer, IDMDToken(address(dmdToken)));
        console.log("  [6/6] Vesting:", address(vesting));

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

        scheduler.startEmissions();
        console.log("  Emissions started (7-day epochs, 18% annual decay)");

        distributor.startDistribution();
        console.log("  Distribution started");
        console.log("");
    }

    function _mintTestTokens(address deployer) internal {
        console.log("Step 4: Minting test tBTC...");
        tbtc.mint(deployer, 100 * 1e18); // 100 tBTC with 18 decimals
        console.log("  Minted 100 tBTC to deployer");
        console.log("");
    }

    function _saveDeployment(address deployer) internal {
        console.log("Step 5: Saving deployment...");

        string memory info = string.concat(
            "# DMD Protocol v1.8.8 Deployment - Testnet\n",
            "# tBTC-Only | Flash Loan Protected | Fully Decentralized\n",
            "\n",
            "MOCK_TBTC=", vm.toString(address(tbtc)), "\n",
            "DMD_TOKEN=", vm.toString(address(dmdToken)), "\n",
            "VAULT=", vm.toString(address(vault)), "\n",
            "SCHEDULER=", vm.toString(address(scheduler)), "\n",
            "DISTRIBUTOR=", vm.toString(address(distributor)), "\n",
            "REDEMPTION=", vm.toString(address(redemption)), "\n",
            "VESTING=", vm.toString(address(vesting)), "\n",
            "\n",
            "# Protocol Constants\n",
            "WARMUP_PERIOD=7 days\n",
            "VESTING_PERIOD=3 days\n",
            "EPOCH_DURATION=7 days\n",
            "MAX_WEIGHT_MULTIPLIER=1.48x\n"
        );

        vm.writeFile("deployments/testnet-deployment.env", info);
        console.log("  Saved to deployments/testnet-deployment.env");
        console.log("");
    }

    function _saveMainnetDeployment(address deployer) internal {
        console.log("Saving mainnet deployment...");

        string memory info = string.concat(
            "# DMD Protocol v1.8.8 Deployment - Base Mainnet\n",
            "# tBTC-Only | Flash Loan Protected | Fully Decentralized\n",
            "\n",
            "TBTC=", vm.toString(TBTC_BASE_MAINNET), "\n",
            "DMD_TOKEN=", vm.toString(address(dmdToken)), "\n",
            "VAULT=", vm.toString(address(vault)), "\n",
            "SCHEDULER=", vm.toString(address(scheduler)), "\n",
            "DISTRIBUTOR=", vm.toString(address(distributor)), "\n",
            "REDEMPTION=", vm.toString(address(redemption)), "\n",
            "VESTING=", vm.toString(address(vesting)), "\n",
            "\n",
            "# Protocol Constants\n",
            "WARMUP_PERIOD=7 days\n",
            "VESTING_PERIOD=3 days\n",
            "EPOCH_DURATION=7 days\n",
            "MAX_WEIGHT_MULTIPLIER=1.48x\n"
        );

        vm.writeFile("deployments/mainnet-deployment.env", info);
        console.log("  Saved to deployments/mainnet-deployment.env");
        console.log("");
    }

    function _printSummary() internal view {
        console.log("=====================================");
        console.log("DEPLOYMENT SUCCESSFUL!");
        console.log("=====================================");
        console.log("");
        console.log("CONTRACT ADDRESSES:");
        console.log("  MockTBTC:     ", address(tbtc));
        console.log("  DMDToken:     ", address(dmdToken));
        console.log("  Vault:        ", address(vault));
        console.log("  Scheduler:    ", address(scheduler));
        console.log("  Distributor:  ", address(distributor));
        console.log("  Redemption:   ", address(redemption));
        console.log("  Vesting:      ", address(vesting));
        console.log("");
        console.log("PROTOCOL FEATURES:");
        console.log("  - tBTC-Only (immutable, no registry)");
        console.log("  - Flash Loan Protection:");
        console.log("    - 7-day warmup (weight = 0)");
        console.log("    - 3-day linear vesting");
        console.log("  - Weight multiplier: 1.0x - 1.48x");
        console.log("  - 7-day epochs, 18% annual decay");
        console.log("  - 14.4M DMD max supply");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("  1. Verify contracts on Basescan");
        console.log("  2. Test locking: vault.lock(amount, months)");
        console.log("  3. Wait 7+ days for warmup to complete");
        console.log("  4. Claim rewards from distributor");
        console.log("");
    }

    function _printMainnetSummary() internal view {
        console.log("=====================================");
        console.log("MAINNET DEPLOYMENT SUCCESSFUL!");
        console.log("=====================================");
        console.log("");
        console.log("CONTRACT ADDRESSES:");
        console.log("  tBTC (real):  ", TBTC_BASE_MAINNET);
        console.log("  DMDToken:     ", address(dmdToken));
        console.log("  Vault:        ", address(vault));
        console.log("  Scheduler:    ", address(scheduler));
        console.log("  Distributor:  ", address(distributor));
        console.log("  Redemption:   ", address(redemption));
        console.log("  Vesting:      ", address(vesting));
        console.log("");
        console.log("IMPORTANT: Protocol is now LIVE and IMMUTABLE");
        console.log("No admin keys, no upgrades, no changes possible");
        console.log("");
    }
}
