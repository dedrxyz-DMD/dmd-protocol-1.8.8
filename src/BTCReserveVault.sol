// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BTCAssetRegistry.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title BTCReserveVault
 * @notice Multi-asset BTC locking vault with duration-based weight calculation
 * @dev Lock duration: 1-24+ months, weight multiplier capped at 1.48x
 * @dev Supports multiple BTC assets via BTCAssetRegistry (WBTC, cbBTC, tBTC, etc.)
 */
contract BTCReserveVault {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error InvalidAmount();
    error InvalidDuration();
    error PositionNotFound();
    error PositionLocked();
    error BTCAssetNotApproved();
    error WrongBTCAsset();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_WEIGHT_MONTHS = 24;
    uint256 public constant WEIGHT_PER_MONTH = 20; // 0.02 in basis points (20/1000)
    uint256 public constant WEIGHT_BASE = 1000; // 1.0x in basis points

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    BTCAssetRegistry public immutable assetRegistry;
    address public immutable redemptionEngine;

    struct Position {
        address btcAsset;        // Which BTC asset is locked
        uint256 amount;          // Amount locked
        uint256 lockMonths;      // Duration in months
        uint256 lockTime;        // Timestamp of lock
        uint256 weight;          // Calculated weight at lock time
    }

    // user => positionId => Position
    mapping(address => mapping(uint256 => Position)) public positions;

    // user => total positions count
    mapping(address => uint256) public positionCount;

    // user => total weight across all positions
    mapping(address => uint256) public totalWeightOf;

    // btcAsset => total amount locked for that asset
    mapping(address => uint256) public totalLockedByAsset;

    uint256 public totalSystemWeight;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Locked(
        address indexed user,
        address indexed btcAsset,
        uint256 indexed positionId,
        uint256 amount,
        uint256 lockMonths,
        uint256 weight
    );

    event Redeemed(
        address indexed user,
        address indexed btcAsset,
        uint256 indexed positionId,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _assetRegistry, address _redemptionEngine) {
        if (_assetRegistry == address(0) || _redemptionEngine == address(0)) {
            revert InvalidAmount();
        }
        assetRegistry = BTCAssetRegistry(_assetRegistry);
        redemptionEngine = _redemptionEngine;
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock BTC asset for specified duration
     * @param btcAsset Address of the BTC asset to lock (must be approved in registry)
     * @param amount Amount to lock
     * @param lockMonths Duration in months (1-24+ allowed, weight capped at 24)
     * @return positionId The ID of the newly created position
     */
    function lock(address btcAsset, uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0) revert InvalidDuration();

        // Validate BTC asset is approved
        if (!assetRegistry.isApprovedBTC(btcAsset)) {
            revert BTCAssetNotApproved();
        }

        // Calculate weight: 1.0 + min(lockMonths, 24) * 0.02
        uint256 weight = calculateWeight(amount, lockMonths);

        // Create position BEFORE external call (reentrancy protection)
        positionId = positionCount[msg.sender];
        positions[msg.sender][positionId] = Position({
            btcAsset: btcAsset,
            amount: amount,
            lockMonths: lockMonths,
            lockTime: block.timestamp,
            weight: weight
        });

        positionCount[msg.sender]++;
        totalWeightOf[msg.sender] += weight;
        totalLockedByAsset[btcAsset] += amount;
        totalSystemWeight += weight;

        // Transfer BTC asset from user (external call LAST - CEI pattern)
        bool success = IERC20Minimal(btcAsset).transferFrom(msg.sender, address(this), amount);
        require(success, "BTC_TRANSFER_FAILED");

        emit Locked(msg.sender, btcAsset, positionId, amount, lockMonths, weight);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem position (backward compatibility wrapper for old single-asset interface)
     * @param user Position owner
     * @param positionId Position identifier
     * @dev This is a compatibility function - used by RedemptionEngine
     */
    function redeem(address user, uint256 positionId) external {
        if (msg.sender != redemptionEngine) revert Unauthorized();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();

        // Check lock expiration
        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        if (block.timestamp < unlockTime) revert PositionLocked();

        // Remove position
        delete positions[user][positionId];
        totalWeightOf[user] -= pos.weight;
        totalLockedByAsset[pos.btcAsset] -= pos.amount;
        totalSystemWeight -= pos.weight;

        // Transfer BTC asset to user
        bool success = IERC20Minimal(pos.btcAsset).transfer(user, pos.amount);
        require(success, "BTC_TRANSFER_FAILED");

        emit Redeemed(user, pos.btcAsset, positionId, pos.amount);
    }

    /**
     * @notice Release BTC from position (called by RedemptionEngine only)
     * @param user Position owner
     * @param positionId Position identifier
     * @param btcAsset Expected BTC asset (safety check)
     * @param amount Expected amount (safety check)
     */
    function releaseBTC(
        address user,
        uint256 positionId,
        address btcAsset,
        uint256 amount
    ) external {
        if (msg.sender != redemptionEngine) revert Unauthorized();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();

        // Safety checks
        if (pos.btcAsset != btcAsset) revert WrongBTCAsset();
        require(pos.amount == amount, "AMOUNT_MISMATCH");

        // Check lock expiration
        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        if (block.timestamp < unlockTime) revert PositionLocked();

        // Remove position
        delete positions[user][positionId];
        totalWeightOf[user] -= pos.weight;
        totalLockedByAsset[btcAsset] -= pos.amount;
        totalSystemWeight -= pos.weight;

        // Transfer BTC asset to user
        bool success = IERC20Minimal(btcAsset).transfer(user, pos.amount);
        require(success, "BTC_TRANSFER_FAILED");

        emit Redeemed(user, btcAsset, positionId, pos.amount);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get specific position details
     * @return btcAsset The BTC asset locked in this position
     * @return amount The amount locked
     * @return lockMonths The lock duration in months
     * @return unlockTime The timestamp when position unlocks
     * @return weight The weight of this position
     */
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (
            address btcAsset,
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight
        )
    {
        Position memory pos = positions[user][positionId];
        return (
            pos.btcAsset,
            pos.amount,
            pos.lockMonths,
            pos.lockTime + (pos.lockMonths * 30 days),
            pos.weight
        );
    }

    /**
     * @notice Check if position is unlocked
     */
    function isPositionUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        return block.timestamp >= unlockTime;
    }

    /**
     * @notice Get total locked amount for a specific BTC asset
     */
    function getTotalLockedByAsset(address btcAsset) external view returns (uint256) {
        return totalLockedByAsset[btcAsset];
    }

    /**
     * @notice Get total locked WBTC across all positions (backward compatibility)
     * @dev Returns sum of all BTC assets - use with caution as different assets may exist
     */
    function totalLockedWBTC() external view returns (uint256) {
        // This is a compatibility function - in multi-asset context,
        // you should use getTotalLockedByAsset() instead
        // For now, we'll need to query the registry for all assets
        BTCAssetRegistry.BTCAsset[] memory assets = assetRegistry.getActiveBTCAssets();
        uint256 total = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            total += totalLockedByAsset[assets[i].tokenAddress];
        }
        return total;
    }

    /**
     * @notice Get number of positions for a user
     */
    function getUserPositionCount(address user) external view returns (uint256) {
        return positionCount[user];
    }

    /**
     * @notice Calculate weight for given amount and duration (preview)
     */
    function calculateWeight(uint256 amount, uint256 lockMonths)
        public
        pure
        returns (uint256)
    {
        uint256 effectiveMonths = lockMonths > MAX_WEIGHT_MONTHS
            ? MAX_WEIGHT_MONTHS
            : lockMonths;

        return (amount * (WEIGHT_BASE + (effectiveMonths * WEIGHT_PER_MONTH))) / WEIGHT_BASE;
    }

    /**
     * @notice Backward compatible wrapper for isUnlocked (old interface)
     */
    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        return block.timestamp >= unlockTime;
    }
}
