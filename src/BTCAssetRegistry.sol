// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BTCAssetRegistry
 * @notice Registry for approved BTC assets (WBTC, cbBTC, tBTC, native BTC, etc.)
 * @dev Allows protocol to support multiple BTC types without redeployment
 */
contract BTCAssetRegistry is Ownable {
    
    struct BTCAsset {
        address tokenAddress;  // ERC20 address (address(0) for native)
        bool isActive;         // Can be locked in protocol
        bool isNative;         // false = ERC20, true = native BTC bridge
        uint8 decimals;        // Should be 8 for BTC
        string name;           // Display name
        uint256 addedAt;       // Timestamp when added
    }
    
    /// @notice Asset ID => BTCAsset details
    mapping(uint256 => BTCAsset) public btcAssets;
    
    /// @notice Token address => Asset ID (for quick lookup)
    mapping(address => uint256) public addressToAssetId;
    
    /// @notice Next available asset ID
    uint256 public nextAssetId = 1;
    
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event BTCAssetAdded(
        uint256 indexed assetId,
        address indexed token,
        string name
    );
    
    event BTCAssetDeactivated(uint256 indexed assetId);
    
    event BTCAssetActivated(uint256 indexed assetId);
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() Ownable(msg.sender) {}
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add a new BTC asset type to the registry
     * @param tokenAddress Address of the BTC token (address(0) for native bridge)
     * @param isNative True if this is a native BTC bridge, false if ERC20
     * @param name Display name for the asset
     */
    function addBTCAsset(
        address tokenAddress,
        bool isNative,
        string calldata name
    ) external onlyOwner {
        require(addressToAssetId[tokenAddress] == 0, "Asset already added");
        
        uint256 assetId = nextAssetId++;
        
        btcAssets[assetId] = BTCAsset({
            tokenAddress: tokenAddress,
            isActive: true,
            isNative: isNative,
            decimals: 8,
            name: name,
            addedAt: block.timestamp
        });
        
        addressToAssetId[tokenAddress] = assetId;
        
        emit BTCAssetAdded(assetId, tokenAddress, name);
    }
    
    /**
     * @notice Deactivate a BTC asset (emergency use)
     * @param assetId The asset ID to deactivate
     * @dev Existing positions are not affected, but new locks are blocked
     */
    function deactivateAsset(uint256 assetId) external onlyOwner {
        require(btcAssets[assetId].tokenAddress != address(0), "Asset not found");
        btcAssets[assetId].isActive = false;
        emit BTCAssetDeactivated(assetId);
    }
    
    /**
     * @notice Reactivate a previously deactivated asset
     * @param assetId The asset ID to reactivate
     */
    function activateAsset(uint256 assetId) external onlyOwner {
        require(btcAssets[assetId].tokenAddress != address(0), "Asset not found");
        btcAssets[assetId].isActive = true;
        emit BTCAssetActivated(assetId);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if a token address is an approved and active BTC asset
     * @param token The token address to check
     * @return True if the token is approved and active
     */
    function isApprovedBTC(address token) external view returns (bool) {
        uint256 assetId = addressToAssetId[token];
        if (assetId == 0) return false;
        return btcAssets[assetId].isActive;
    }
    
    /**
     * @notice Get all active BTC assets
     * @return Array of all active BTCAsset structs
     */
    function getActiveBTCAssets() external view returns (BTCAsset[] memory) {
        // Count active assets
        uint256 activeCount = 0;
        for (uint256 i = 1; i < nextAssetId; i++) {
            if (btcAssets[i].isActive) {
                activeCount++;
            }
        }
        
        // Build array of active assets
        BTCAsset[] memory active = new BTCAsset[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < nextAssetId; i++) {
            if (btcAssets[i].isActive) {
                active[index] = btcAssets[i];
                index++;
            }
        }
        
        return active;
    }
    
    /**
     * @notice Get asset details by ID
     * @param assetId The asset ID to query
     * @return Asset details
     */
    function getAssetById(uint256 assetId) 
        external 
        view 
        returns (BTCAsset memory) 
    {
        require(btcAssets[assetId].tokenAddress != address(0), "Asset not found");
        return btcAssets[assetId];
    }
    
    /**
     * @notice Get asset ID by token address
     * @param token The token address to query
     * @return The asset ID (0 if not found)
     */
    function getAssetIdByAddress(address token) 
        external 
        view 
        returns (uint256) 
    {
        return addressToAssetId[token];
    }
    
    /**
     * @notice Get total number of assets (active + inactive)
     * @return Total count of assets
     */
    function getTotalAssetCount() external view returns (uint256) {
        return nextAssetId - 1;
    }
}
