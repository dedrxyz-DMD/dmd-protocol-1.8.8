// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title BTCAssetRegistry
 * @notice Immutable registry for approved BTC assets (WBTC, cbBTC, tBTC, etc.)
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev Assets are set at deployment and cannot be modified
 */
contract BTCAssetRegistry {

    struct BTCAsset {
        address tokenAddress;  // ERC20 address
        bool isActive;         // Always true for registered assets
        bool isNative;         // false = ERC20, true = native BTC bridge
        uint8 decimals;        // Token decimals
        string name;           // Display name
        uint256 addedAt;       // Timestamp when added (deployment time)
    }

    /// @notice Asset ID => BTCAsset details
    mapping(uint256 => BTCAsset) public btcAssets;

    /// @notice Token address => Asset ID (for quick lookup)
    mapping(address => uint256) public addressToAssetId;

    /// @notice Total number of registered assets (immutable after deployment)
    uint256 public immutable totalAssets;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BTCAssetRegistered(
        uint256 indexed assetId,
        address indexed token,
        string name,
        uint8 decimals
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy registry with initial set of BTC assets
     * @param tokenAddresses Array of BTC token addresses
     * @param names Array of display names
     * @param decimalValues Array of decimal values for each token
     * @param isNativeFlags Array of flags indicating if asset is native BTC bridge
     * @dev All arrays must have same length. Assets cannot be modified after deployment.
     */
    constructor(
        address[] memory tokenAddresses,
        string[] memory names,
        uint8[] memory decimalValues,
        bool[] memory isNativeFlags
    ) {
        require(tokenAddresses.length > 0, "No assets provided");
        require(
            tokenAddresses.length == names.length &&
            tokenAddresses.length == decimalValues.length &&
            tokenAddresses.length == isNativeFlags.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(tokenAddresses[i] != address(0), "Invalid token address");
            require(addressToAssetId[tokenAddresses[i]] == 0, "Duplicate asset");

            uint256 assetId = i + 1; // Asset IDs start at 1

            btcAssets[assetId] = BTCAsset({
                tokenAddress: tokenAddresses[i],
                isActive: true,
                isNative: isNativeFlags[i],
                decimals: decimalValues[i],
                name: names[i],
                addedAt: block.timestamp
            });

            addressToAssetId[tokenAddresses[i]] = assetId;

            emit BTCAssetRegistered(assetId, tokenAddresses[i], names[i], decimalValues[i]);
        }

        totalAssets = tokenAddresses.length;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a token address is an approved BTC asset
     * @param token The token address to check
     * @return True if the token is registered (always active)
     */
    function isApprovedBTC(address token) external view returns (bool) {
        return addressToAssetId[token] != 0;
    }

    /**
     * @notice Get all registered BTC assets
     * @return Array of all BTCAsset structs
     */
    function getActiveBTCAssets() external view returns (BTCAsset[] memory) {
        BTCAsset[] memory assets = new BTCAsset[](totalAssets);

        for (uint256 i = 0; i < totalAssets; i++) {
            assets[i] = btcAssets[i + 1];
        }

        return assets;
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
        require(assetId > 0 && assetId <= totalAssets, "Asset not found");
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
     * @notice Get total number of registered assets
     * @return Total count of assets
     */
    function getTotalAssetCount() external view returns (uint256) {
        return totalAssets;
    }
}
