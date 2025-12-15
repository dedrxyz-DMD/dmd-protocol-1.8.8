// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/BTCAssetRegistry.sol";

contract MockBTCToken {
    string public name;
    uint8 public decimals = 8;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name) {
        name = _name;
    }

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
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract BTCAssetRegistryTest is Test {
    BTCAssetRegistry public registry;
    
    MockBTCToken public wbtc;
    MockBTCToken public cbBTC;
    MockBTCToken public tBTC;
    
    address public owner;
    address public alice;
    address public bob;

    event BTCAssetAdded(uint256 indexed assetId, address indexed token, string name);
    event BTCAssetDeactivated(uint256 indexed assetId);
    event BTCAssetActivated(uint256 indexed assetId);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy registry
        registry = new BTCAssetRegistry();

        // Deploy mock BTC tokens
        wbtc = new MockBTCToken("Wrapped BTC");
        cbBTC = new MockBTCToken("Coinbase BTC");
        tBTC = new MockBTCToken("Threshold BTC");
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(registry.owner(), owner);
        assertEq(registry.nextAssetId(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        ADD ASSET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddBTCAsset() public {
        vm.expectEmit(true, true, false, true);
        emit BTCAssetAdded(1, address(wbtc), "Wrapped BTC");
        
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");

        // Verify asset was added
        (
            address tokenAddress,
            bool isActive,
            bool isNative,
            uint8 decimals,
            string memory name,
            uint256 addedAt
        ) = registry.btcAssets(1);

        assertEq(tokenAddress, address(wbtc));
        assertTrue(isActive);
        assertFalse(isNative);
        assertEq(decimals, 8);
        assertEq(name, "Wrapped BTC");
        assertGt(addedAt, 0);

        // Verify mapping
        assertEq(registry.addressToAssetId(address(wbtc)), 1);
        
        // Verify next ID incremented
        assertEq(registry.nextAssetId(), 2);
    }

    function test_AddBTCAsset_MultipleAssets() public {
        // Add WBTC
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        // Add cbBTC
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        
        // Add tBTC
        registry.addBTCAsset(address(tBTC), false, "Threshold BTC");

        // Verify all assets
        assertEq(registry.addressToAssetId(address(wbtc)), 1);
        assertEq(registry.addressToAssetId(address(cbBTC)), 2);
        assertEq(registry.addressToAssetId(address(tBTC)), 3);
        assertEq(registry.nextAssetId(), 4);
    }

    function test_AddBTCAsset_NativeAsset() public {
        // Add native BTC (address(0) for native)
        address nativeBTCBridge = makeAddr("nativeBTCBridge");
        
        registry.addBTCAsset(nativeBTCBridge, true, "Native BTC");

        (
            address tokenAddress,
            bool isActive,
            bool isNative,
            ,
            string memory name,
        ) = registry.btcAssets(1);

        assertEq(tokenAddress, nativeBTCBridge);
        assertTrue(isActive);
        assertTrue(isNative);
        assertEq(name, "Native BTC");
    }

    function test_AddBTCAsset_RevertsIfAlreadyAdded() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        vm.expectRevert("Asset already added");
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC Again");
    }

    function test_AddBTCAsset_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVAL CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsApprovedBTC_ActiveAsset() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        assertTrue(registry.isApprovedBTC(address(wbtc)));
    }

    function test_IsApprovedBTC_NotAdded() public {
        assertFalse(registry.isApprovedBTC(address(wbtc)));
    }

    function test_IsApprovedBTC_Deactivated() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.deactivateAsset(1);
        
        assertFalse(registry.isApprovedBTC(address(wbtc)));
    }

    /*//////////////////////////////////////////////////////////////
                        DEACTIVATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeactivateAsset() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        vm.expectEmit(true, false, false, false);
        emit BTCAssetDeactivated(1);
        
        registry.deactivateAsset(1);

        (
            ,
            bool isActive,
            ,
            ,
            ,
        ) = registry.btcAssets(1);

        assertFalse(isActive);
        assertFalse(registry.isApprovedBTC(address(wbtc)));
    }

    function test_DeactivateAsset_RevertsIfNotFound() public {
        vm.expectRevert("Asset not found");
        registry.deactivateAsset(1);
    }

    function test_DeactivateAsset_RevertsIfNotOwner() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        vm.prank(alice);
        vm.expectRevert();
        registry.deactivateAsset(1);
    }

    /*//////////////////////////////////////////////////////////////
                        ACTIVATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ActivateAsset() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.deactivateAsset(1);
        
        vm.expectEmit(true, false, false, false);
        emit BTCAssetActivated(1);
        
        registry.activateAsset(1);

        (
            ,
            bool isActive,
            ,
            ,
            ,
        ) = registry.btcAssets(1);

        assertTrue(isActive);
        assertTrue(registry.isApprovedBTC(address(wbtc)));
    }

    function test_ActivateAsset_RevertsIfNotFound() public {
        vm.expectRevert("Asset not found");
        registry.activateAsset(1);
    }

    function test_ActivateAsset_RevertsIfNotOwner() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.deactivateAsset(1);
        
        vm.prank(alice);
        vm.expectRevert();
        registry.activateAsset(1);
    }

    /*//////////////////////////////////////////////////////////////
                        GET ACTIVE ASSETS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetActiveBTCAssets_Empty() public {
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 0);
    }

    function test_GetActiveBTCAssets_Single() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0].tokenAddress, address(wbtc));
        assertTrue(assets[0].isActive);
        assertEq(assets[0].name, "Wrapped BTC");
    }

    function test_GetActiveBTCAssets_Multiple() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        registry.addBTCAsset(address(tBTC), false, "Threshold BTC");
        
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 3);
        
        assertEq(assets[0].tokenAddress, address(wbtc));
        assertEq(assets[1].tokenAddress, address(cbBTC));
        assertEq(assets[2].tokenAddress, address(tBTC));
    }

    function test_GetActiveBTCAssets_OnlyActive() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        registry.addBTCAsset(address(tBTC), false, "Threshold BTC");
        
        // Deactivate cbBTC
        registry.deactivateAsset(2);
        
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 2);
        
        assertEq(assets[0].tokenAddress, address(wbtc));
        assertEq(assets[1].tokenAddress, address(tBTC));
    }

    function test_GetActiveBTCAssets_ReactivateIncluded() public {
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        
        // Deactivate and reactivate
        registry.deactivateAsset(2);
        registry.activateAsset(2);
        
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 2);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership() public {
        registry.transferOwnership(alice);
        
        assertEq(registry.owner(), alice);
        
        // Old owner can't add assets
        vm.expectRevert();
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        // New owner can add assets
        vm.prank(alice);
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        
        assertEq(registry.addressToAssetId(address(wbtc)), 1);
    }

    function test_RenounceOwnership() public {
        registry.renounceOwnership();
        
        assertEq(registry.owner(), address(0));
        
        // No one can add assets
        vm.expectRevert();
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_AddMultipleAssetsAndManage() public {
        // Add 3 different BTC assets
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        registry.addBTCAsset(address(cbBTC), false, "Coinbase BTC");
        registry.addBTCAsset(address(tBTC), false, "Threshold BTC");

        // All should be approved
        assertTrue(registry.isApprovedBTC(address(wbtc)));
        assertTrue(registry.isApprovedBTC(address(cbBTC)));
        assertTrue(registry.isApprovedBTC(address(tBTC)));

        // Deactivate cbBTC (security issue discovered)
        registry.deactivateAsset(2);
        assertFalse(registry.isApprovedBTC(address(cbBTC)));

        // WBTC and tBTC still work
        assertTrue(registry.isApprovedBTC(address(wbtc)));
        assertTrue(registry.isApprovedBTC(address(tBTC)));

        // Get active assets
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 2);

        // Reactivate cbBTC (issue fixed)
        registry.activateAsset(2);
        assertTrue(registry.isApprovedBTC(address(cbBTC)));

        // All 3 active again
        assets = registry.getActiveBTCAssets();
        assertEq(assets.length, 3);
    }

    function test_Scenario_EmergencyPause() public {
        // Add asset
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        assertTrue(registry.isApprovedBTC(address(wbtc)));

        // Emergency: exploit found in WBTC contract
        registry.deactivateAsset(1);
        
        // Asset immediately unusable
        assertFalse(registry.isApprovedBTC(address(wbtc)));

        // After fix, reactivate
        registry.activateAsset(1);
        assertTrue(registry.isApprovedBTC(address(wbtc)));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_AddBTCAsset_RandomNames(string calldata randomName) public {
        vm.assume(bytes(randomName).length > 0 && bytes(randomName).length < 100);
        
        registry.addBTCAsset(address(wbtc), false, randomName);
        
        (
            ,
            ,
            ,
            ,
            string memory name,
        ) = registry.btcAssets(1);
        
        assertEq(name, randomName);
    }

    function testFuzz_MultipleAssetsCannotDuplicate(address[] calldata tokens) public {
        vm.assume(tokens.length > 0 && tokens.length <= 10);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.assume(tokens[i] != address(0));
            
            // Skip if already added
            if (registry.addressToAssetId(tokens[i]) != 0) {
                continue;
            }
            
            registry.addBTCAsset(tokens[i], false, "Test Asset");
            
            // Verify cannot add again
            vm.expectRevert("Asset already added");
            registry.addBTCAsset(tokens[i], false, "Duplicate");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GAS BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    function test_Gas_AddSingleAsset() public {
        uint256 gasBefore = gasleft();
        registry.addBTCAsset(address(wbtc), false, "Wrapped BTC");
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas to add single asset", gasUsed);
        assertLt(gasUsed, 200000); // Should be under 200k gas
    }

    function test_Gas_GetActiveAssets_10Assets() public {
        // Add 10 assets
        for (uint256 i = 0; i < 10; i++) {
            address mockToken = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            registry.addBTCAsset(mockToken, false, string(abi.encodePacked("Asset ", i)));
        }
        
        uint256 gasBefore = gasleft();
        BTCAssetRegistry.BTCAsset[] memory assets = registry.getActiveBTCAssets();
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas to get 10 active assets", gasUsed);
        assertEq(assets.length, 10);
    }
}
