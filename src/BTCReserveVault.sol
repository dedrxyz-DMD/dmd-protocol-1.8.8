// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title BTCReserveVault - tBTC locking vault with duration-based weight
/// @author DMD Protocol Team
/// @notice Lock tBTC to earn weight for DMD emissions
/// @dev Fully decentralized, tBTC-only on Base chain, flash loan protected via 7-day warmup + 3-day vesting
contract BTCReserveVault {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error InvalidDuration();
    error PositionNotFound();
    error PositionLocked();
    error Unauthorized();
    error AlreadyRequestedEarlyUnlock();
    error NoEarlyUnlockRequested();
    error EarlyUnlockNotReady();

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

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice tBTC token address on Base
    address public immutable TBTC;
    /// @notice RedemptionEngine contract address
    address public immutable redemptionEngine;

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

    /// @notice User positions: user => positionId => Position
    mapping(address => mapping(uint256 => Position)) public positions;
    /// @notice Total position count per user
    mapping(address => uint256) public positionCount;
    /// @notice Total raw weight per user
    mapping(address => uint256) public totalWeightOf;
    /// @notice Active position IDs per user
    mapping(address => uint256[]) internal activePositions;
    /// @notice Position ID to index in activePositions array
    mapping(address => mapping(uint256 => uint256)) internal positionIndex;

    /// @notice Total tBTC locked in vault
    uint256 public totalLocked;
    /// @notice Total raw system weight
    uint256 public totalSystemWeight;
    /// @notice Cached total vested weight (updated via updateVestedWeightCache)
    uint256 public cachedTotalVestedWeight;
    /// @notice Last update timestamp for cached weight
    uint256 public lastWeightCacheUpdate;

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
    /// @notice Emitted when early unlock is requested
    event EarlyUnlockRequested(address indexed user, uint256 indexed positionId, uint256 unlockTime);
    /// @notice Emitted when early unlock is cancelled
    event EarlyUnlockCancelled(address indexed user, uint256 indexed positionId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize vault with tBTC and RedemptionEngine addresses
    /// @param _tbtc tBTC token address
    /// @param _redemptionEngine RedemptionEngine contract address
    constructor(address _tbtc, address _redemptionEngine) {
        if (_tbtc == address(0) || _redemptionEngine == address(0)) revert InvalidAmount();
        TBTC = _tbtc;
        redemptionEngine = _redemptionEngine;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lock tBTC to earn weight for DMD emissions
    /// @param amount Amount of tBTC to lock (18 decimals)
    /// @param lockMonths Duration in months (1-60)
    /// @return positionId The ID of the created position
    function lock(uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0 || lockMonths > MAX_LOCK_MONTHS) revert InvalidDuration();

        // Track new user
        if (!isUser[msg.sender]) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
            emit UserRegistered(msg.sender, block.timestamp);
        }

        uint256 weight = calculateWeight(amount, lockMonths);
        positionId = positionCount[msg.sender];

        positions[msg.sender][positionId] = Position(amount, lockMonths, block.timestamp, weight);
        positionCount[msg.sender]++;
        totalWeightOf[msg.sender] += weight;
        totalLocked += amount;
        totalSystemWeight += weight;

        // Track active position
        positionIndex[msg.sender][positionId] = activePositions[msg.sender].length;
        activePositions[msg.sender].push(positionId);

        require(IERC20(TBTC).transferFrom(msg.sender, address(this), amount), "TRANSFER_FAILED");
        emit Locked(msg.sender, positionId, amount, lockMonths, weight);
    }

    /// @notice Redeem tBTC from an unlocked position (called by RedemptionEngine only)
    /// @param user Position owner address
    /// @param positionId Position ID to redeem
    function redeem(address user, uint256 positionId) external {
        if (msg.sender != redemptionEngine) revert Unauthorized();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();

        // Check if unlocked: normal unlock OR early unlock (30-day delay passed)
        bool normalUnlock = block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days);
        uint256 requestTime = earlyUnlockRequestTime[user][positionId];
        bool earlyUnlock = requestTime != 0 && block.timestamp >= requestTime + EARLY_UNLOCK_DELAY;

        if (!normalUnlock && !earlyUnlock) revert PositionLocked();

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
        uint256 index = positionIndex[user][positionId];
        uint256 lastIndex = activePositions[user].length - 1;
        if (index != lastIndex) {
            uint256 lastPositionId = activePositions[user][lastIndex];
            activePositions[user][index] = lastPositionId;
            positionIndex[user][lastPositionId] = index;
        }
        activePositions[user].pop();
        delete positionIndex[user][positionId];

        require(IERC20(TBTC).transfer(user, pos.amount), "TRANSFER_FAILED");
        emit Redeemed(user, positionId, pos.amount);
    }

    /// @notice Request early unlock for a position (30-day waiting period)
    /// @dev Weight is removed immediately upon request. User stops earning rewards.
    /// @param positionId Position ID to request early unlock for
    function requestEarlyUnlock(uint256 positionId) external {
        Position memory pos = positions[msg.sender][positionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (earlyUnlockRequestTime[msg.sender][positionId] != 0) revert AlreadyRequestedEarlyUnlock();

        // Check if already unlocked normally (no need for early unlock)
        if (block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days)) revert PositionLocked();

        // Set early unlock request time
        earlyUnlockRequestTime[msg.sender][positionId] = block.timestamp;

        // Remove weight from system immediately (user stops earning rewards)
        totalWeightOf[msg.sender] -= pos.weight;
        totalSystemWeight -= pos.weight;

        emit EarlyUnlockRequested(msg.sender, positionId, block.timestamp + EARLY_UNLOCK_DELAY);
    }

    /// @notice Cancel early unlock request and restore weight
    /// @param positionId Position ID to cancel early unlock for
    function cancelEarlyUnlock(uint256 positionId) external {
        Position memory pos = positions[msg.sender][positionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (earlyUnlockRequestTime[msg.sender][positionId] == 0) revert NoEarlyUnlockRequested();

        // Clear early unlock request
        delete earlyUnlockRequestTime[msg.sender][positionId];

        // Restore weight to system
        totalWeightOf[msg.sender] += pos.weight;
        totalSystemWeight += pos.weight;

        emit EarlyUnlockCancelled(msg.sender, positionId);
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

    /// @notice Get total vested weight across ALL users (uses cache if fresh)
    /// @dev Returns cached value if updated within last hour, otherwise calculates
    /// @return Total system vested weight
    function getTotalVestedWeight() external view returns (uint256) {
        // Use cache if updated within last hour
        if (block.timestamp - lastWeightCacheUpdate < 1 hours && cachedTotalVestedWeight > 0) {
            return cachedTotalVestedWeight;
        }
        // Fallback to calculation (may fail at scale)
        return _calculateTotalVestedWeight(0, allUsers.length);
    }

    /// @notice Update the cached total vested weight (paginated for gas efficiency)
    /// @dev Call with startIndex=0, maxUsers=100 repeatedly until all users processed
    /// @param startIndex Starting user index
    /// @param maxUsers Maximum users to process in this call
    /// @return processedCount Number of users processed
    /// @return isComplete True if all users have been processed
    function updateVestedWeightCache(uint256 startIndex, uint256 maxUsers) external returns (uint256 processedCount, bool isComplete) {
        uint256 userLen = allUsers.length;
        if (startIndex >= userLen) {
            return (0, true);
        }

        uint256 endIndex = startIndex + maxUsers;
        if (endIndex > userLen) {
            endIndex = userLen;
        }

        uint256 batchWeight = _calculateTotalVestedWeight(startIndex, endIndex);
        processedCount = endIndex - startIndex;
        isComplete = (endIndex >= userLen);

        if (startIndex == 0) {
            // First batch - reset cache
            cachedTotalVestedWeight = batchWeight;
        } else {
            // Subsequent batch - add to cache
            cachedTotalVestedWeight += batchWeight;
        }

        if (isComplete) {
            lastWeightCacheUpdate = block.timestamp;
            emit WeightCacheUpdated(cachedTotalVestedWeight, userLen, block.timestamp);
        }

        return (processedCount, isComplete);
    }

    /// @notice Internal function to calculate vested weight for a range of users
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

    /// @notice Calculate weight for given amount and duration
    /// @param amount tBTC amount
    /// @param lockMonths Lock duration (capped at MAX_WEIGHT_MONTHS for bonus)
    /// @return Calculated weight
    function calculateWeight(uint256 amount, uint256 lockMonths) public pure returns (uint256) {
        uint256 months = lockMonths > MAX_WEIGHT_MONTHS ? MAX_WEIGHT_MONTHS : lockMonths;
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
}
