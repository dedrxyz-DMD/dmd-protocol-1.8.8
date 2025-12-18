// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title BTCReserveVault
 * @notice tBTC locking vault with duration-based weight calculation
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev Only accepts tBTC on Base chain (immutable)
 * @dev Lock duration: 1-24+ months, weight multiplier capped at 1.48x
 * @dev Flash loan protection: 7-day warmup before weight becomes effective
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

    /// @notice tBTC token address on Base mainnet (immutable, only accepted asset)
    address public constant TBTC = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b;

    uint256 public constant MAX_WEIGHT_MONTHS = 24;
    uint256 public constant WEIGHT_PER_MONTH = 20; // 0.02 in basis points (20/1000)
    uint256 public constant WEIGHT_BASE = 1000; // 1.0x in basis points

    /// @notice Warmup period before weight becomes effective (flash loan protection)
    uint256 public constant WEIGHT_WARMUP_PERIOD = 7 days;

    /// @notice Linear vesting period after warmup
    uint256 public constant WEIGHT_VESTING_PERIOD = 3 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable redemptionEngine;

    struct Position {
        uint256 amount;          // Amount of tBTC locked
        uint256 lockMonths;      // Duration in months
        uint256 lockTime;        // Timestamp of lock
        uint256 weight;          // Calculated weight at lock time
    }

    // user => positionId => Position
    mapping(address => mapping(uint256 => Position)) public positions;

    // user => total positions count
    mapping(address => uint256) public positionCount;

    // user => total weight across all positions (raw, not vested)
    mapping(address => uint256) public totalWeightOf;

    // Total tBTC locked in vault
    uint256 public totalLocked;

    // Total system weight (raw, not vested)
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

    constructor(address _redemptionEngine) {
        if (_redemptionEngine == address(0)) {
            revert InvalidAmount();
        }
        redemptionEngine = _redemptionEngine;
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock tBTC for specified duration
     * @param amount Amount of tBTC to lock
     * @param lockMonths Duration in months (1-24+ allowed, weight capped at 24)
     * @return positionId The ID of the newly created position
     * @dev Weight only becomes effective after WEIGHT_WARMUP_PERIOD (flash loan protection)
     */
    function lock(uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0) revert InvalidDuration();

        // Calculate weight: 1.0 + min(lockMonths, 24) * 0.02
        uint256 weight = calculateWeight(amount, lockMonths);

        // Create position BEFORE external call (reentrancy protection)
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
        bool success = IERC20(TBTC).transferFrom(msg.sender, address(this), amount);
        require(success, "TBTC_TRANSFER_FAILED");

        emit Locked(msg.sender, positionId, amount, lockMonths, weight);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem position (called by RedemptionEngine only)
     * @param user Position owner
     * @param positionId Position identifier
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
        bool success = IERC20(TBTC).transfer(user, pos.amount);
        require(success, "TBTC_TRANSFER_FAILED");

        emit Redeemed(user, positionId, pos.amount);
    }

    /*//////////////////////////////////////////////////////////////
                    VESTED WEIGHT CALCULATIONS
                    (Flash Loan Protection)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get vested weight for a single position
     * @param user Position owner
     * @param positionId Position identifier
     * @return Vested weight (0 during warmup, linear increase during vesting)
     * @dev This is the weight that counts for emissions - prevents flash loans
     */
    function getPositionVestedWeight(address user, uint256 positionId) public view returns (uint256) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return 0;

        uint256 elapsed = block.timestamp - pos.lockTime;

        // During warmup period: no weight
        if (elapsed < WEIGHT_WARMUP_PERIOD) {
            return 0;
        }

        // After warmup + vesting: full weight
        if (elapsed >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD) {
            return pos.weight;
        }

        // During vesting period: linear increase
        uint256 vestingElapsed = elapsed - WEIGHT_WARMUP_PERIOD;
        return (pos.weight * vestingElapsed) / WEIGHT_VESTING_PERIOD;
    }

    /**
     * @notice Get total vested weight for a user across all positions
     * @param user User address
     * @return Total vested weight
     * @dev Used by MintDistributor for emission calculations
     */
    function getVestedWeight(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256 count = positionCount[user];

        for (uint256 i = 0; i < count; i++) {
            total += getPositionVestedWeight(user, i);
        }

        return total;
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get specific position details
     * @return amount The amount of tBTC locked
     * @return lockMonths The lock duration in months
     * @return unlockTime The timestamp when position unlocks
     * @return weight The weight of this position
     */
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight
        )
    {
        Position memory pos = positions[user][positionId];
        return (
            pos.amount,
            pos.lockMonths,
            pos.lockTime + (pos.lockMonths * 30 days),
            pos.weight
        );
    }

    /**
     * @notice Get extended position details including vested weight
     */
    function getPositionExtended(address user, uint256 positionId)
        external
        view
        returns (
            uint256 amount,
            uint256 lockMonths,
            uint256 unlockTime,
            uint256 weight,
            uint256 vestedWeight,
            bool isFullyVested
        )
    {
        Position memory pos = positions[user][positionId];
        uint256 vested = getPositionVestedWeight(user, positionId);

        return (
            pos.amount,
            pos.lockMonths,
            pos.lockTime + (pos.lockMonths * 30 days),
            pos.weight,
            vested,
            vested == pos.weight && pos.weight > 0
        );
    }

    /**
     * @notice Get total locked tBTC in vault
     */
    function getTotalLocked() external view returns (uint256) {
        return totalLocked;
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
     * @notice Check if position is unlocked (lock period expired)
     */
    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        return block.timestamp >= unlockTime;
    }

    /**
     * @notice Check if position weight is fully vested
     */
    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;

        uint256 elapsed = block.timestamp - pos.lockTime;
        return elapsed >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD;
    }
}
