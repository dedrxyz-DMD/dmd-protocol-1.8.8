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
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount && allowance[from][msg.sender] >= amount, "Insufficient");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @title DeployDMDFresh - DMD Protocol v1.8.8 Deployment
/// @dev tBTC-only, fully decentralized, no admin
contract DeployDMDFresh is Script {
    MockTBTC public tbtc;
    BTCReserveVault public vault;
    EmissionScheduler public scheduler;
    MintDistributor public distributor;
    DMDToken public dmdToken;
    RedemptionEngine public redemption;
    VestingContract public vesting;

    address constant MAINNET_TBTC = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("DMD Protocol v1.8.8 | Deployer:", deployer);
        require(deployer.balance >= 0.01 ether, "Need 0.01 ETH");

        vm.startBroadcast(pk);

        // Deploy MockTBTC for testnet
        tbtc = new MockTBTC();
        console.log("MockTBTC:", address(tbtc));

        // Compute addresses for circular dependencies
        // Order: Vault, Scheduler, Distributor, Token, Redemption, Vesting
        uint256 nonce = vm.getNonce(deployer);
        address pVault = vm.computeCreateAddress(deployer, nonce);
        address pScheduler = vm.computeCreateAddress(deployer, nonce + 1);
        address pDistributor = vm.computeCreateAddress(deployer, nonce + 2);
        address pToken = vm.computeCreateAddress(deployer, nonce + 3);
        address pRedemption = vm.computeCreateAddress(deployer, nonce + 4);
        address pVesting = vm.computeCreateAddress(deployer, nonce + 5);

        // Deploy contracts in order
        vault = new BTCReserveVault(address(tbtc), pRedemption);
        require(address(vault) == pVault, "Vault mismatch");

        scheduler = new EmissionScheduler(pDistributor);
        require(address(scheduler) == pScheduler, "Scheduler mismatch");

        distributor = new MintDistributor(IDMDToken(pToken), IBTCReserveVault(address(vault)), IEmissionScheduler(address(scheduler)));
        require(address(distributor) == pDistributor, "Distributor mismatch");

        // DMDToken now takes both distributor and vesting addresses
        dmdToken = new DMDToken(address(distributor), pVesting);
        require(address(dmdToken) == pToken, "Token mismatch");

        redemption = new RedemptionEngine(IDMDToken(address(dmdToken)), IBTCReserveVault(address(vault)));
        require(address(redemption) == pRedemption, "Redemption mismatch");

        // VestingContract - can now mint directly (no external funding needed)
        address[] memory bens = new address[](1);
        uint256[] memory allocs = new uint256[](1);
        bens[0] = deployer;
        allocs[0] = 3_600_000e18; // 3.6M DMD for team (20% of max supply)
        vesting = new VestingContract(IDMDToken(address(dmdToken)), bens, allocs);
        require(address(vesting) == pVesting, "Vesting mismatch");

        // Mint test tBTC
        tbtc.mint(deployer, 100e18);

        vm.stopBroadcast();

        // Log addresses
        console.log("Vault:", address(vault));
        console.log("Scheduler:", address(scheduler));
        console.log("Distributor:", address(distributor));
        console.log("DMDToken:", address(dmdToken));
        console.log("Redemption:", address(redemption));
        console.log("Vesting:", address(vesting));
    }
}
