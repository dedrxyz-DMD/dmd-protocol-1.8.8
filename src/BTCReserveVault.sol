// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @notice Minimal ERC20 interface
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Interface for MintDistributor to register first lock
interface IMintDistributorRegistry {
    function registerUserFirstLock(address user) external;
    function clearPositionDmdMinted(address user, uint256 positionId) external;
}

/// @notice Interface for PDC adapter status check
interface IPDC {
    function isAdapterActive(address adapter) external view returns (bool);
}

/// @title BTCReserveVault - tBTC locking vault with duration-based weight
/// @author DMD Protocol Team
/// @notice Lock tBTC to earn weight for DMD emissions
/// @dev Fully decentralized, tBTC-only on Base chain, flash loan protected via 7-day warmup + 3-day vesting
/// @dev v1.8.9 - Security fixes: improved cache management, bounded loops, reentrancy protection
contract BTCReserveVault {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error ZeroAddressNotAllowed();
    error InvalidLockDuration();
    error PositionNotFound();
    error PositionStillLocked();
    error PositionAlreadyUnlocked();
    error UnauthorizedCaller();
    error EarlyUnlockAlreadyRequested();
    error NoEarlyUnlockPending();
    error ReentrancyGuard();
    error TransferFailed();
    error AdapterNotActive();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum months for weight calculation bonus (24 months = 1.48x)
    uint256 public constant MAX_WEIGHT_MONTHS = 24;
    /// @notice Weight bonus per month locked (20 = 2% per month)
    uint256 public constant WEIGHT_PER_MONTH = 20;
    /// @notice Base weight divisor (1000 = 100%)
    uint256 public constant WEIGHT_BASE = 1000;
    /// @notice Warmup period before weight starts vesting (flash loan protection)
    uint256 public constant WEIGHT_WARMUP_PERIOD = 7 days;
    /// @notice Linear vesting period after warmup
    uint256 public constant WEIGHT_VESTING_PERIOD = 3 days;
    /// @notice Maximum lock duration allowed (60 months = 5 years)
    uint256 public constant MAX_LOCK_MONTHS = 60;
    /// @notice Delay period for early unlock requests (30 days)
    uint256 public constant EARLY_UNLOCK_DELAY = 30 days;
    /// @notice Maximum users to process in a single cache update call
    uint256 public constant MAX_USERS_PER_CACHE_UPDATE = 100;
    /// @notice Cache validity period (15 minutes - reduced for accuracy)
    uint256 public constant CACHE_VALIDITY_PERIOD = 15 minutes;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice tBTC token address on Base
    address public immutable TBTC;
    /// @notice RedemptionEngine contract address
    address public immutable REDEMPTION_ENGINE;
    /// @notice MintDistributor contract address (for first lock registration)
    address public immutable MINT_DISTRIBUTOR;
    /// @notice Protocol Defense Consensus contract (for adapter status checks)
    address public immutable PDC;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Position data for locked tBTC
    /// @param amount Amount of tBTC locked
    /// @param lockMonths Lock duration in months
    /// @param lockTime Timestamp when position was created
    /// @param weight Calculated weight for this position
    struct Position {
        uint256 amount;
        uint256 lockMonths;
        uint256 lockTime;
        uint256 weight;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    /// @notice User positions: user => positionId => Position
    mapping(address => mapping(uint256 => Position)) public positions;
    /// @notice Total position count per user
    mapping(address => uint256) public positionCount;
    /// @notice Total raw weight per user (excluding early unlock requests)
    mapping(address => uint256) public totalWeightOf;
    /// @notice Active position IDs per user
    mapping(address => uint256[]) internal activePositions;
    /// @notice Position ID to index in activePositions array
    mapping(address => mapping(uint256 => uint256)) internal positionIndex;

    /// @notice Total tBTC locked in vault
    uint256 public totalLocked;
    /// @notice Total raw system weight (excluding early unlock requests)
    uint256 public totalSystemWeight;
    /// @notice Cached total vested weight (updated via updateVestedWeightCache)
    uint256 public cachedTotalVestedWeight;
    /// @notice Last update timestamp for cached weight
    uint256 public lastWeightCacheUpdate;
    /// @notice Last user index processed in cache update (for pagination)
    uint256 public cacheUpdateLastIndex;
    /// @notice Whether cache update is in progress
    bool public cacheUpdateInProgress;

    /// @notice All users who have ever locked
    address[] public allUsers;
    /// @notice Whether address has locked before
    mapping(address => bool) public isUser;
    /// @notice Early unlock request time: user => positionId => requestTime (0 = no request)
    mapping(address => mapping(uint256 => uint256)) public earlyUnlockRequestTime;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new user registers by locking for the first time
    event UserRegistered(address indexed user, uint256 timestamp);
    /// @notice Emitted when tBTC is locked
    event Locked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 lockMonths, uint256 weight);
    /// @notice Emitted when tBTC is redeemed
    event Redeemed(address indexed user, uint256 indexed positionId, uint256 amount);
    /// @notice Emitted when vested weight cache is updated
    event WeightCacheUpdated(uint256 totalVestedWeight, uint256 usersProcessed, uint256 timestamp);
    /// @notice Emitted when cache update progress is made
    event WeightCacheProgress(uint256 startIndex, uint256 endIndex, uint256 batchWeight, uint256 timestamp);
    /// @notice Emitted when early unlock is requested
    event EarlyUnlockRequested(address indexed user, uint256 indexed positionId, uint256 unlockTime);
    /// @notice Emitted when early unlock is cancelled
    event EarlyUnlockCancelled(address indexed user, uint256 indexed positionId);
    /// @notice Emitted when cache update progress is reset
    event CacheUpdateReset(uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Prevents reentrancy attacks
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_locked == 2) revert ReentrancyGuard();
        _locked = 2;
    }

    function _nonReentrantAfter() private {
        _locked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize vault with tBTC, RedemptionEngine, MintDistributor, and PDC addresses
    /// @param _tbtc tBTC token address
    /// @param _redemptionEngine RedemptionEngine contract address
    /// @param _mintDistributor MintDistributor contract address
    /// @param _pdc Protocol Defense Consensus contract address
    constructor(address _tbtc, address _redemptionEngine, address _mintDistributor, address _pdc) {
        if (_tbtc == address(0) || _redemptionEngine == address(0) || _mintDistributor == address(0) || _pdc == address(0)) revert ZeroAddressNotAllowed();
        TBTC = _tbtc;
        REDEMPTION_ENGINE = _redemptionEngine;
        MINT_DISTRIBUTOR = _mintDistributor;
        PDC = _pdc;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lock tBTC to earn weight for DMD emissions
    /// @dev Checks PDC adapter status once PDC is activated
    /// @param amount Amount of tBTC to lock (18 decimals)
    /// @param lockMonths Duration in months (1-60)
    /// @return positionId The ID of the created position
    function lock(uint256 amount, uint256 lockMonths) external nonReentrant returns (uint256 positionId) {
        if (amount == 0) revert ZeroAmount();
        if (lockMonths == 0 || lockMonths > MAX_LOCK_MONTHS) revert InvalidLockDuration();

        // Check PDC adapter status (only enforced after PDC activation)
        // Before activation: tBTC works by default (pre-approved in PDC constructor)
        // After activation: PDC governance can pause/deprecate if compromised
        if (!_isAdapterActive(TBTC)) revert AdapterNotActive();

        // Track new user and register with MintDistributor
        bool isNewUser = !isUser[msg.sender];
        if (isNewUser) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
            emit UserRegistered(msg.sender, block.timestamp);

            // Register first lock time with MintDistributor for eligibility tracking
            try IMintDistributorRegistry(MINT_DISTRIBUTOR).registerUserFirstLock(msg.sender) {} catch {}
        }

        uint256 weight = calculateWeight(amount, lockMonths);
        positionId = positionCount[msg.sender];

        positions[msg.sender][positionId] = Position({
            amount: amount,
            lockMonths: lockMonths,
            lockTime: block.timestamp,
            weight: weight
        });
        positionCount[msg.sender]++;
        totalWeightOf[msg.sender] += weight;
        totalLocked += amount;
        totalSystemWeight += weight;

        // Track active position
        positionIndex[msg.sender][positionId] = activePositions[msg.sender].length;
        activePositions[msg.sender].push(positionId);

        // Transfer tBTC from user (using SafeTransfer pattern)
        uint256 balanceBefore = IERC20(TBTC).balanceOf(address(this));
        bool success = IERC20(TBTC).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        uint256 balanceAfter = IERC20(TBTC).balanceOf(address(this));
        if (balanceAfter - balanceBefore != amount) revert TransferFailed();

        emit Locked(msg.sender, positionId, amount, lockMonths, weight);
    }

    /// @notice Redeem tBTC from an unlocked position (called by RedemptionEngine only)
    /// @param user Position owner address
    /// @param positionId Position ID to redeem
    function redeem(address user, uint256 positionId) external nonReentrant {
        if (msg.sender != REDEMPTION_ENGINE) revert UnauthorizedCaller();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();

        // Check if unlocked: normal unlock OR early unlock (30-day delay passed)
        bool normalUnlock = block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days);
        uint256 requestTime = earlyUnlockRequestTime[user][positionId];
        bool earlyUnlock = requestTime != 0 && block.timestamp >= requestTime + EARLY_UNLOCK_DELAY;

        if (!normalUnlock && !earlyUnlock) revert PositionStillLocked();

        // Delete position BEFORE external call (CEI pattern)
        delete positions[user][positionId];
        totalLocked -= pos.amount;

        // Only subtract weight if NOT early unlock (early unlock already removed weight)
        if (requestTime == 0) {
            totalWeightOf[user] -= pos.weight;
            totalSystemWeight -= pos.weight;
        } else {
            // Clear early unlock request
            delete earlyUnlockRequestTime[user][positionId];
        }

        // Remove from active positions (swap and pop)
        _removeFromActivePositions(user, positionId);

        // SECURITY FIX: Clear DMD minted tracking for this position
        // This prevents position ID reuse from accumulating old DMD debts
        try IMintDistributorRegistry(MINT_DISTRIBUTOR).clearPositionDmdMinted(user, positionId) {} catch {}

        // Transfer tBTC back to user
        bool success = IERC20(TBTC).transfer(user, pos.amount);
        if (!success) revert TransferFailed();

        emit Redeemed(user, positionId, pos.amount);
    }

    /// @notice Request early unlock for a position (30-day waiting period)
    /// @dev Weight is removed immediately upon request. User stops earning rewards.
    /// @param positionId Position ID to request early unlock for
    function requestEarlyUnlock(uint256 positionId) external nonReentrant {
        Position memory pos = positions[msg.sender][positionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (earlyUnlockRequestTime[msg.sender][positionId] != 0) revert EarlyUnlockAlreadyRequested();

        // Check if already unlocked normally (no need for early unlock)
        if (block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days)) revert PositionAlreadyUnlocked();

        // Set early unlock request time
        earlyUnlockRequestTime[msg.sender][positionId] = block.timestamp;

        // Remove weight from system immediately (user stops earning rewards)
        totalWeightOf[msg.sender] -= pos.weight;
        totalSystemWeight -= pos.weight;

        emit EarlyUnlockRequested(msg.sender, positionId, block.timestamp + EARLY_UNLOCK_DELAY);
    }

    /// @notice Cancel early unlock request and restore weight
    /// @param positionId Position ID to cancel early unlock for
    function cancelEarlyUnlock(uint256 positionId) external nonReentrant {
        Position memory pos = positions[msg.sender][positionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (earlyUnlockRequestTime[msg.sender][positionId] == 0) revert NoEarlyUnlockPending();

        // Clear early unlock request
        delete earlyUnlockRequestTime[msg.sender][positionId];

        // Restore weight to system
        totalWeightOf[msg.sender] += pos.weight;
        totalSystemWeight += pos.weight;

        emit EarlyUnlockCancelled(msg.sender, positionId);
    }

    /// @notice Update the cached total vested weight (paginated for gas efficiency)
    /// @dev SECURITY FIX #9: Bounded loop - processes max MAX_USERS_PER_CACHE_UPDATE users per call
    /// @dev Call repeatedly until isComplete returns true
    /// @return processedCount Number of users processed in this call
    /// @return isComplete True if all users have been processed
    function updateVestedWeightCache() external returns (uint256 processedCount, bool isComplete) {
        uint256 userLen = allUsers.length;

        // Determine start index
        uint256 startIndex = 0;
        if (cacheUpdateInProgress) {
            startIndex = cacheUpdateLastIndex;
        } else {
            // Starting fresh - reset cache
            cachedTotalVestedWeight = 0;
            cacheUpdateInProgress = true;
        }

        if (startIndex >= userLen) {
            // All done
            cacheUpdateInProgress = false;
            cacheUpdateLastIndex = 0;
            lastWeightCacheUpdate = block.timestamp;
            emit WeightCacheUpdated(cachedTotalVestedWeight, userLen, block.timestamp);
            return (0, true);
        }

        // Calculate end index (bounded)
        uint256 endIndex = startIndex + MAX_USERS_PER_CACHE_UPDATE;
        if (endIndex > userLen) {
            endIndex = userLen;
        }

        // Calculate batch weight
        uint256 batchWeight = _calculateTotalVestedWeight(startIndex, endIndex);
        cachedTotalVestedWeight += batchWeight;

        processedCount = endIndex - startIndex;
        isComplete = (endIndex >= userLen);
        cacheUpdateLastIndex = endIndex;

        emit WeightCacheProgress(startIndex, endIndex, batchWeight, block.timestamp);

        if (isComplete) {
            cacheUpdateInProgress = false;
            cacheUpdateLastIndex = 0;
            lastWeightCacheUpdate = block.timestamp;
            emit WeightCacheUpdated(cachedTotalVestedWeight, userLen, block.timestamp);
        }

        return (processedCount, isComplete);
    }

    /// @notice Legacy function for backward compatibility
    /// @dev Delegates to new updateVestedWeightCache()
    function updateVestedWeightCache(uint256, uint256) external returns (uint256 processedCount, bool isComplete) {
        return this.updateVestedWeightCache();
    }

    /// @notice Force reset cache update progress (in case of stuck state)
    /// @dev SECURITY FIX: Only resets progress flags, does NOT zero the cached weight
    /// @dev This prevents griefing attacks that could zero the cache maliciously
    function resetCacheUpdate() external {
        cacheUpdateInProgress = false;
        cacheUpdateLastIndex = 0;
        // NOTE: Intentionally NOT resetting cachedTotalVestedWeight to prevent griefing
        // The cache will be recalculated on next updateVestedWeightCache() call
        emit CacheUpdateReset(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get vested weight for a single position
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return Vested weight (0 during warmup, 0 if early unlock requested, linear during vesting, full after)
    function getPositionVestedWeight(address user, uint256 positionId) public view returns (uint256) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return 0;

        // If early unlock requested, weight is 0 (already removed from system)
        if (earlyUnlockRequestTime[user][positionId] != 0) return 0;

        uint256 elapsed = block.timestamp - pos.lockTime;
        if (elapsed < WEIGHT_WARMUP_PERIOD) return 0;
        if (elapsed >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD) return pos.weight;

        return (pos.weight * (elapsed - WEIGHT_WARMUP_PERIOD)) / WEIGHT_VESTING_PERIOD;
    }

    /// @notice Get total vested weight for a user
    /// @param user User address
    /// @return Total vested weight across all active positions
    function getVestedWeight(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] memory active = activePositions[user];
        uint256 len = active.length;
        for (uint256 i = 0; i < len;) {
            total += getPositionVestedWeight(user, active[i]);
            unchecked { ++i; }
        }
        return total;
    }

    /// @notice Get total vested weight across ALL users
    /// @dev SECURITY FIX #5: Returns cached value only if valid, otherwise calculates with safety limit
    /// @return Total system vested weight
    function getTotalVestedWeight() external view returns (uint256) {
        // Cache must be fresh (within validity period) and not in progress
        if (cacheUpdateInProgress) {
            // Cache update in progress - calculate fresh (may fail for large user counts)
            return _calculateTotalVestedWeightSafe();
        }

        if (block.timestamp - lastWeightCacheUpdate < CACHE_VALIDITY_PERIOD && cachedTotalVestedWeight > 0) {
            return cachedTotalVestedWeight;
        }

        // Cache is stale - try to calculate fresh
        return _calculateTotalVestedWeightSafe();
    }

    /// @notice Check if cache is valid and fresh
    /// @return True if cache can be used
    function isCacheValid() external view returns (bool) {
        return !cacheUpdateInProgress &&
               block.timestamp - lastWeightCacheUpdate < CACHE_VALIDITY_PERIOD &&
               cachedTotalVestedWeight > 0;
    }

    /// @notice Get cache status information
    /// @return inProgress Whether cache update is in progress
    /// @return lastUpdate Last cache update timestamp
    /// @return cachedWeight Cached total vested weight
    /// @return lastIndex Last processed user index
    function getCacheStatus() external view returns (
        bool inProgress,
        uint256 lastUpdate,
        uint256 cachedWeight,
        uint256 lastIndex
    ) {
        return (cacheUpdateInProgress, lastWeightCacheUpdate, cachedTotalVestedWeight, cacheUpdateLastIndex);
    }

    /// @notice Get position details
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return amount Locked tBTC amount
    /// @return lockMonths Lock duration in months
    /// @return unlockTime Timestamp when position unlocks
    /// @return weight Position weight
    function getPosition(address user, uint256 positionId) external view returns (uint256 amount, uint256 lockMonths, uint256 unlockTime, uint256 weight) {
        Position memory pos = positions[user][positionId];
        return (pos.amount, pos.lockMonths, pos.lockTime + (pos.lockMonths * 30 days), pos.weight);
    }

    /// @notice Get position lock time
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return Lock timestamp
    function getPositionLockTime(address user, uint256 positionId) external view returns (uint256) {
        return positions[user][positionId].lockTime;
    }

    /// @notice Calculate weight for given amount and duration
    /// @dev Weight Formula: weight = amount * (1 + min(lockMonths, 24) * 0.02)
    /// @dev Examples:
    /// @dev   - 1 month lock:  1.02x multiplier (amount * 1020 / 1000)
    /// @dev   - 12 month lock: 1.24x multiplier (amount * 1240 / 1000)
    /// @dev   - 24 month lock: 1.48x multiplier (amount * 1480 / 1000) - MAXIMUM
    /// @dev   - 60 month lock: 1.48x multiplier (capped at 24 months for bonus)
    /// @param amount tBTC amount (18 decimals)
    /// @param lockMonths Lock duration in months (1-60, bonus capped at 24)
    /// @return Calculated weight with duration bonus applied
    function calculateWeight(uint256 amount, uint256 lockMonths) public pure returns (uint256) {
        // Cap bonus months at MAX_WEIGHT_MONTHS (24) for weight calculation
        // Longer locks still work but don't get additional weight bonus
        uint256 months = lockMonths > MAX_WEIGHT_MONTHS ? MAX_WEIGHT_MONTHS : lockMonths;
        // Formula: amount * (1000 + months * 20) / 1000 = amount * (1 + months * 0.02)
        return (amount * (WEIGHT_BASE + (months * WEIGHT_PER_MONTH))) / WEIGHT_BASE;
    }

    /// @notice Check if position is unlocked (normal or early unlock)
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return True if position exists and (lock period passed OR early unlock ready)
    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        // Normal unlock: lock period has passed
        if (block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days)) return true;

        // Early unlock: request made and 30-day delay passed
        uint256 requestTime = earlyUnlockRequestTime[user][positionId];
        if (requestTime != 0 && block.timestamp >= requestTime + EARLY_UNLOCK_DELAY) return true;

        return false;
    }

    /// @notice Check if position weight is fully vested
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return True if warmup + vesting period has passed
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        return pos.amount > 0 && block.timestamp - pos.lockTime >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD;
    }

    /// @notice Get total tBTC locked in vault
    function getTotalLocked() external view returns (uint256) { return totalLocked; }

    /// @notice Get total position count for user (including redeemed)
    function getUserPositionCount(address user) external view returns (uint256) { return positionCount[user]; }

    /// @notice Get active position count for user
    function getActivePositionCount(address user) external view returns (uint256) { return activePositions[user].length; }

    /// @notice Get array of active position IDs for user
    function getActivePositions(address user) external view returns (uint256[] memory) { return activePositions[user]; }

    /// @notice Get total registered user count
    function getTotalUsers() external view returns (uint256) { return allUsers.length; }

    /// @notice Get user address by index
    /// @param index User index in allUsers array
    /// @return User address
    function getUserByIndex(uint256 index) external view returns (address) {
        if (index >= allUsers.length) return address(0);
        return allUsers[index];
    }

    /// @notice Get early unlock status for a position
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return requested True if early unlock was requested
    /// @return readyTime Timestamp when early unlock will be ready (0 if not requested)
    /// @return isReady True if early unlock is ready now
    function getEarlyUnlockStatus(address user, uint256 positionId) external view returns (bool requested, uint256 readyTime, bool isReady) {
        uint256 requestTime = earlyUnlockRequestTime[user][positionId];
        if (requestTime == 0) {
            return (false, 0, false);
        }
        uint256 ready = requestTime + EARLY_UNLOCK_DELAY;
        return (true, ready, block.timestamp >= ready);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Remove position from active positions array
    /// @param user User address
    /// @param positionId Position ID to remove
    function _removeFromActivePositions(address user, uint256 positionId) internal {
        uint256 index = positionIndex[user][positionId];
        uint256 lastIndex = activePositions[user].length - 1;

        if (index != lastIndex) {
            uint256 lastPositionId = activePositions[user][lastIndex];
            activePositions[user][index] = lastPositionId;
            positionIndex[user][lastPositionId] = index;
        }

        activePositions[user].pop();
        delete positionIndex[user][positionId];
    }

    /// @notice Calculate vested weight for a range of users
    /// @param startIndex Starting user index
    /// @param endIndex Ending user index (exclusive)
    /// @return Total vested weight for the range
    function _calculateTotalVestedWeight(uint256 startIndex, uint256 endIndex) internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = startIndex; i < endIndex;) {
            address user = allUsers[i];
            uint256[] memory active = activePositions[user];
            uint256 posLen = active.length;
            for (uint256 j = 0; j < posLen;) {
                total += getPositionVestedWeight(user, active[j]);
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
        return total;
    }

    /// @notice Calculate total vested weight with bounded iteration
    /// @dev SECURITY FIX #9: Limits iteration to prevent out-of-gas
    /// @dev SECURITY FIX #10: Returns totalSystemWeight as fallback instead of potentially zero cache
    /// @return Total vested weight (may return fallback value if user count is very large)
    function _calculateTotalVestedWeightSafe() internal view returns (uint256) {
        uint256 userLen = allUsers.length;
        // Limit to reasonable number to prevent gas issues
        uint256 maxUsers = 500;
        if (userLen > maxUsers) {
            // For large user counts, return cached value if available
            if (cachedTotalVestedWeight > 0) {
                return cachedTotalVestedWeight;
            }
            // SECURITY FIX: If cache is zero/unset, use totalSystemWeight as upper bound
            // This is an approximation but prevents zero-weight DoS attacks
            // totalSystemWeight is always >= actual vested weight
            return totalSystemWeight;
        }
        return _calculateTotalVestedWeight(0, userLen);
    }

    /// @notice Check if adapter is active via PDC
    /// @dev Returns true if PDC says adapter is active (approved, not paused, not deprecated)
    /// @param adapter Adapter address to check
    /// @return True if adapter can receive deposits
    function _isAdapterActive(address adapter) internal view returns (bool) {
        return IPDC(PDC).isAdapterActive(adapter);
    }
}
