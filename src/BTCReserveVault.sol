// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title BTCReserveVault
 * @notice WBTC locking vault with duration-based weight calculation
 * @dev Lock duration: 1-24+ months, weight multiplier capped at 1.48x
 */
contract BTCReserveVault {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error InvalidAmount();
    error InvalidDuration();
    error PositionNotFound();
    error LockNotExpired();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_WEIGHT_MONTHS = 24;
    uint256 public constant WEIGHT_PER_MONTH = 20; // 0.02 in basis points (20/1000)
    uint256 public constant WEIGHT_BASE = 1000; // 1.0x in basis points

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable wbtc;
    address public immutable redemptionEngine;

    struct Position {
        uint256 amount;          // WBTC locked
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

    uint256 public totalLockedWBTC;
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

    constructor(address _wbtc, address _redemptionEngine) {
        if (_wbtc == address(0) || _redemptionEngine == address(0)) {
            revert InvalidAmount();
        }
        wbtc = _wbtc;
        redemptionEngine = _redemptionEngine;
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lock WBTC for specified duration
     * @param amount WBTC amount to lock
     * @param lockMonths Duration in months (1-24+ allowed, weight capped at 24)
     */
    function lock(uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0) revert InvalidDuration();

        // Calculate weight: 1.0 + min(lockMonths, 24) * 0.02
        uint256 effectiveMonths = lockMonths > MAX_WEIGHT_MONTHS 
            ? MAX_WEIGHT_MONTHS 
            : lockMonths;
        
        uint256 weight = (amount * (WEIGHT_BASE + (effectiveMonths * WEIGHT_PER_MONTH))) / WEIGHT_BASE;

        // Transfer WBTC from user
        bool success = IERC20Minimal(wbtc).transferFrom(msg.sender, address(this), amount);
        require(success, "WBTC_TRANSFER_FAILED");

        // Create position
        positionId = positionCount[msg.sender];
        positions[msg.sender][positionId] = Position({
            amount: amount,
            lockMonths: lockMonths,
            lockTime: block.timestamp,
            weight: weight
        });

        positionCount[msg.sender]++;
        totalWeightOf[msg.sender] += weight;
        totalLockedWBTC += amount;
        totalSystemWeight += weight;

        emit Locked(msg.sender, positionId, amount, lockMonths, weight);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem WBTC from position (called by RedemptionEngine only)
     * @param user Position owner
     * @param positionId Position identifier
     */
    function redeem(address user, uint256 positionId) external {
        if (msg.sender != redemptionEngine) revert Unauthorized();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();

        // Check lock expiration
        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        if (block.timestamp < unlockTime) revert LockNotExpired();

        // Remove position
        delete positions[user][positionId];
        totalWeightOf[user] -= pos.weight;
        totalLockedWBTC -= pos.amount;
        totalSystemWeight -= pos.weight;

        // Transfer WBTC to user
        bool success = IERC20Minimal(wbtc).transfer(user, pos.amount);
        require(success, "WBTC_TRANSFER_FAILED");

        emit Redeemed(user, positionId, pos.amount);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's total weight across all positions
     */
    function getUserWeight(address user) external view returns (uint256) {
        return totalWeightOf[user];
    }

    /**
     * @notice Get specific position details
     */
    function getPosition(address user, uint256 positionId) 
        external 
        view 
        returns (
            uint256 amount,
            uint256 lockMonths,
            uint256 lockTime,
            uint256 weight,
            uint256 unlockTime
        ) 
    {
        Position memory pos = positions[user][positionId];
        return (
            pos.amount,
            pos.lockMonths,
            pos.lockTime,
            pos.weight,
            pos.lockTime + (pos.lockMonths * 30 days)
        );
    }

    /**
     * @notice Check if position is unlocked
     */
    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return false;
        
        uint256 unlockTime = pos.lockTime + (pos.lockMonths * 30 days);
        return block.timestamp >= unlockTime;
    }

    /**
     * @notice Calculate weight for given amount and duration (preview)
     */
    function calculateWeight(uint256 amount, uint256 lockMonths) 
        external 
        pure 
        returns (uint256) 
    {
        uint256 effectiveMonths = lockMonths > MAX_WEIGHT_MONTHS 
            ? MAX_WEIGHT_MONTHS 
            : lockMonths;
        
        return (amount * (WEIGHT_BASE + (effectiveMonths * WEIGHT_PER_MONTH))) / WEIGHT_BASE;
    }
}