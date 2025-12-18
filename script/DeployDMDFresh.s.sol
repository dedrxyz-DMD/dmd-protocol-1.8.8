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
 * @notice Mock tBTC token for testnet deployment
 * @dev 18 decimals to match real tBTC on Base
 */
contract MockTBTC {
    string public constant name = "Mock tBTC";
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
 * @notice Deployment script for DMD Protocol v1.8.8
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev tBTC-only on Base chain (immutable)
 */
contract DeployDMDFresh is Script {
    // Deployed contract instances
    MockTBTC public tbtc;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    // Real tBTC address on Base mainnet
    address constant MAINNET_TBTC = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        _printHeader(deployer);

        vm.startBroadcast(deployerPrivateKey);

        _deployMockTBTC();
        _deployProtocol(deployer);
        _mintTestTokens(deployer);

        vm.stopBroadcast();

        _saveDeployment();
        _printSummary();
    }

    function _printHeader(address deployer) internal view {
        console.log("=====================================");
        console.log("DMD PROTOCOL v1.8.8 - FRESH DEPLOYMENT");
        console.log("tBTC-Only | Fully Decentralized");
        console.log("=====================================");
        console.log("Network: Base Sepolia Testnet");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        require(deployer.balance >= 0.01 ether, "Need at least 0.01 ETH");
    }

    function _deployMockTBTC() internal {
        console.log("Step 1: Deploying Mock tBTC for testnet...");
        tbtc = new MockTBTC();
        console.log("  MockTBTC:", address(tbtc));
        console.log("");
    }

    function _deployProtocol(address deployer) internal {
        console.log("Step 2: Deploying protocol contracts...");
        console.log("  Computing deterministic addresses...");

        // Compute addresses using CREATE prediction
        uint256 nonce = vm.getNonce(deployer);

        // Order: Vault, Scheduler, Distributor, Token, Redemption, Vesting
        address pVault = vm.computeCreateAddress(deployer, nonce);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 1);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 2);
        address pToken = vm.computeCreateAddress(deployer, nonce + 3);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 4);

        console.log("  Predicted addresses:");
        console.log("    Vault:", pVault);
        console.log("    Scheduler:", pScheduler);
        console.log("    Distributor:", pDistributor);
        console.log("    Token:", pToken);
        console.log("    Redemption:", pRedemption);
        console.log("");

        // Deploy BTCReserveVault (needs tBTC + predicted redemption)
        vault = new BTCReserveVault(address(tbtc), pRedemption);
        console.log("  [1/6] BTCReserveVault:", address(vault));
        require(address(vault) == pVault, "Vault address mismatch");

        // Deploy EmissionScheduler (needs predicted distributor, auto-starts)
        scheduler = new EmissionScheduler(pDistributor);
        console.log("  [2/6] EmissionScheduler:", address(scheduler));
        require(address(scheduler) == pScheduler, "Scheduler address mismatch");

        // Deploy MintDistributor (needs predicted token + actual vault + actual scheduler)
        distributor = new MintDistributor(
            IDMDToken(pToken),
            IBTCReserveVault(address(vault)),
            IEmissionScheduler(address(scheduler))
        );
        console.log("  [3/6] MintDistributor:", address(distributor));
        require(address(distributor) == pDistributor, "Distributor address mismatch");

        // Deploy DMDToken (needs actual distributor)
        dmdToken = new DMDToken(address(distributor));
        console.log("  [4/6] DMDToken:", address(dmdToken));
        require(address(dmdToken) == pToken, "Token address mismatch");

        // Deploy RedemptionEngine (needs actual token + actual vault)
        redemption = new RedemptionEngine(
            IDMDToken(address(dmdToken)),
            IBTCReserveVault(address(vault))
        );
        console.log("  [5/6] RedemptionEngine:", address(redemption));
        require(address(redemption) == pRedemption, "Redemption address mismatch");

        // Deploy VestingContract (needs actual token + beneficiaries)
        address[] memory beneficiaries = new address[](1);
        uint256[] memory allocations = new uint256[](1);
        beneficiaries[0] = deployer;
        allocations[0] = 3_600_000e18; // 3.6M DMD for team (20% of max supply)

        vesting = new VestingContract(
            IDMDToken(address(dmdToken)),
            beneficiaries,
            allocations
        );
        console.log("  [6/6] VestingContract:", address(vesting));

        console.log("");
        console.log("  All addresses verified!");
        console.log("  Emissions auto-started at deployment");
        console.log("");
    }

    function _mintTestTokens(address deployer) internal {
        console.log("Step 3: Minting test tBTC...");
        tbtc.mint(deployer, 100e18); // 100 tBTC for testing
        console.log("  Minted 100 tBTC to deployer");
        console.log("");
    }

    function _saveDeployment() internal {
        console.log("Step 4: Saving deployment info...");

        string memory info = string.concat(
            "# DMD Protocol v1.8.8 Deployment\n",
            "# Network: Base Sepolia Testnet\n",
            "# tBTC-Only | Fully Decentralized\n\n",
            "TBTC=", vm.toString(address(tbtc)), "\n",
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
        console.log("Contract Addresses:");
        console.log("  tBTC (Mock):     ", address(tbtc));
        console.log("  DMDToken:        ", address(dmdToken));
        console.log("  BTCReserveVault: ", address(vault));
        console.log("  EmissionScheduler:", address(scheduler));
        console.log("  MintDistributor: ", address(distributor));
        console.log("  RedemptionEngine:", address(redemption));
        console.log("  VestingContract: ", address(vesting));
        console.log("");
        console.log("Protocol Features:");
        console.log("  - tBTC-only (no other BTC variants)");
        console.log("  - Fully decentralized (no owner/admin)");
        console.log("  - Emissions auto-started");
        console.log("  - Flash loan protection (7d warmup + 3d vesting)");
        console.log("");
        console.log("Test Commands:");
        console.log("  1. Approve tBTC: tbtc.approve(vault, amount)");
        console.log("  2. Lock tBTC: vault.lock(amount, months)");
        console.log("  3. Wait 7+ days for weight to vest");
        console.log("  4. Finalize epoch: distributor.finalizeEpoch()");
        console.log("  5. Claim DMD: distributor.claim(epochId)");
        console.log("");
    }
}
