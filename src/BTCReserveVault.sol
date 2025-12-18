// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title BTCReserveVault
 * @notice tBTC-only locking vault with duration-based weight and flash loan protection
 * @dev Fully decentralized: no owner, no admin, immutable parameters
 * @dev Flash loan protection: 7-day warmup + 3-day linear vesting before weight counts
 * @dev Lock duration: 1-120 months, weight multiplier capped at 1.48x (at 24 months)
 */
contract BTCReserveVault {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error InvalidDuration();
    error PositionNotFound();
    error PositionLocked();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum months for weight bonus (1.0 + 24 * 0.02 = 1.48x)
    uint256 public constant MAX_WEIGHT_MONTHS = 24;

    /// @notice Weight bonus per month: 2% = 20/1000
    uint256 public constant WEIGHT_PER_MONTH = 20;

    /// @notice Base weight multiplier: 1.0 = 1000/1000
    uint256 public constant WEIGHT_BASE = 1000;

    /// @notice Warmup period before weight starts vesting (7 days)
    uint256 public constant WARMUP_PERIOD = 7 days;

    /// @notice Vesting period for weight to become fully active (3 days)
    uint256 public constant VESTING_PERIOD = 3 days;

    /// @notice Total time for full weight: warmup + vesting = 10 days
    uint256 public constant FULL_VEST_TIME = WARMUP_PERIOD + VESTING_PERIOD;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice tBTC token address (immutable, set at deployment)
    address public immutable TBTC;

    /// @notice Redemption engine address (only contract that can release BTC)
    address public immutable redemptionEngine;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Position {
        uint256 amount;          // Amount of tBTC locked
        uint256 lockMonths;      // Duration in months
        uint256 lockTime;        // Timestamp when locked
        uint256 weight;          // Max weight (after full vesting)
    }

    /// @notice user => positionId => Position
    mapping(address => mapping(uint256 => Position)) public positions;

    /// @notice user => total positions count
    mapping(address => uint256) public positionCount;

    /// @notice user => total max weight across all positions (before vesting)
    mapping(address => uint256) public totalWeightOf;

    /// @notice Total tBTC locked in the vault
    uint256 public totalLocked;

    /// @notice Total max system weight (sum of all position weights before vesting)
    uint256 public totalSystemWeight;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Locked(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 lockMonths,
        uint256 weight
    );

    event Redeemed(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy vault with tBTC address
     * @param _tbtc Address of tBTC token
     * @param _redemptionEngine Address of redemption engine contract
     * @dev Both addresses are immutable after deployment
     */
    constructor(address _tbtc, address _redemptionEngine) {
        if (_tbtc == address(0) || _redemptionEngine == address(0)) {
            revert InvalidAmount();
        }
        TBTC = _tbtc;
        redemptionEngine = _redemptionEngine;
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock tBTC for specified duration
     * @param amount Amount of tBTC to lock (18 decimals)
     * @param lockMonths Duration in months (1-120, weight capped at 24)
     * @return positionId The ID of the newly created position
     * @dev Weight starts at 0, then vests linearly after 7-day warmup over 3 days
     */
    function lock(uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0) revert InvalidDuration();

        // Calculate max weight: 1.0 + min(lockMonths, 24) * 0.02
        uint256 weight = calculateWeight(amount, lockMonths);

        // Create position BEFORE external call (reentrancy protection via CEI)
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

        // Transfer tBTC from user (external call LAST - CEI pattern)
        bool success = IERC20Minimal(TBTC).transferFrom(msg.sender, address(this), amount);
        require(success, "TBTC_TRANSFER_FAILED");

        emit Locked(msg.sender, positionId, amount, lockMonths, weight);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Release tBTC from position (called by RedemptionEngine only)
     * @param user Position owner
     * @param positionId Position identifier
     * @dev Only redemptionEngine can call this after user burns DMD
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
        totalLocked -= pos.amount;
        totalSystemWeight -= pos.weight;

        // Transfer tBTC to user
        bool success = IERC20Minimal(TBTC).transfer(user, pos.amount);
        require(success, "TBTC_TRANSFER_FAILED");

        emit Redeemed(user, positionId, pos.amount);
    }

    /*//////////////////////////////////////////////////////////////
                      VESTING CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate vested weight for a specific position
     * @param user Position owner
     * @param positionId Position identifier
     * @return Vested weight (0 during warmup, linear increase during vesting, full after)
     */
    function getPositionVestedWeight(address user, uint256 positionId) public view returns (uint256) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return 0;

        uint256 elapsed = block.timestamp - pos.lockTime;

        // During warmup period: 0 weight
        if (elapsed < WARMUP_PERIOD) {
            return 0;
        }

        // After full vest time: full weight
        if (elapsed >= FULL_VEST_TIME) {
            return pos.weight;
        }

        // During vesting period: linear interpolation
        uint256 vestingElapsed = elapsed - WARMUP_PERIOD;
        return (pos.weight * vestingElapsed) / VESTING_PERIOD;
    }

    /**
     * @notice Calculate total vested weight for a user across all positions
     * @param user User address
     * @return Total vested weight
     */
    function getVestedWeight(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256 count = positionCount[user];

        for (uint256 i = 0; i < count; i++) {
            total += getPositionVestedWeight(user, i);
        }

        return total;
    }

    /**
     * @notice Check if position weight is fully vested
     * @param user Position owner
     * @param positionId Position identifier
     * @return True if weight is fully vested (10+ days since lock)
     */
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        return block.timestamp >= pos.lockTime + FULL_VEST_TIME;
    }

    /**
     * @notice Get vesting status of a position
     * @param user Position owner
     * @param positionId Position identifier
     * @return vestingPercent Percentage of weight vested (0-100)
     * @return timeToFullVest Seconds until fully vested (0 if already vested)
     */
    function getVestingStatus(address user, uint256 positionId)
        external
        view
        returns (uint256 vestingPercent, uint256 timeToFullVest)
    {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return (0, 0);

        uint256 elapsed = block.timestamp - pos.lockTime;

        if (elapsed >= FULL_VEST_TIME) {
            return (100, 0);
        }

        if (elapsed < WARMUP_PERIOD) {
            return (0, FULL_VEST_TIME - elapsed);
        }

        uint256 vestingElapsed = elapsed - WARMUP_PERIOD;
        vestingPercent = (vestingElapsed * 100) / VESTING_PERIOD;
        timeToFullVest = FULL_VEST_TIME - elapsed;
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get specific position details
     * @return btcAsset Always returns TBTC address (for interface compatibility)
     * @return amount The amount locked
     * @return lockMonths The lock duration in months
     * @return unlockTime The timestamp when position unlocks
     * @return weight The max weight of this position
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
            TBTC,
            pos.amount,
            pos.lockMonths,
            pos.lockTime + (pos.lockMonths * 30 days),
            pos.weight
        );
    }

    /**
     * @notice Check if position lock period has expired
     * @param user Position owner
     * @param positionId Position identifier
     * @return True if lock period has expired
     */
    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        return block.timestamp >= unlockTime;
    }

    /**
     * @notice Get number of positions for a user
     */
    function getUserPositionCount(address user) external view returns (uint256) {
        return positionCount[user];
    }

    /**
     * @notice Calculate max weight for given amount and duration
     * @param amount Amount of tBTC
     * @param lockMonths Lock duration in months
     * @return Max weight (before vesting)
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
     * @notice Get time remaining until position unlocks
     * @param user Position owner
     * @param positionId Position identifier
     * @return Seconds until unlock (0 if already unlocked or position doesn't exist)
     */
    function getTimeToUnlock(address user, uint256 positionId) external view returns (uint256) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return 0;

        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        if (block.timestamp >= unlockTime) return 0;

        return unlockTime - block.timestamp;
    }

    /**
     * @notice Backward compatible wrapper for totalLockedWBTC
     * @return Total tBTC locked in the vault
     */
    function totalLockedWBTC() external view returns (uint256) {
        return totalLocked;
    }
}
