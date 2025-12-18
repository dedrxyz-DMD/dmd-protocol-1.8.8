// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title BTCReserveVault - tBTC locking vault with duration-based weight
/// @dev Fully decentralized, tBTC-only on Base chain, flash loan protected
/// @dev Tracks all users for accurate vested weight calculation
contract BTCReserveVault {
    error InvalidAmount();
    error InvalidDuration();
    error PositionNotFound();
    error PositionLocked();
    error Unauthorized();

    address public immutable TBTC;
    address public immutable redemptionEngine;

    uint256 public constant MAX_WEIGHT_MONTHS = 24;
    uint256 public constant WEIGHT_PER_MONTH = 20;
    uint256 public constant WEIGHT_BASE = 1000;
    uint256 public constant WEIGHT_WARMUP_PERIOD = 7 days;
    uint256 public constant WEIGHT_VESTING_PERIOD = 3 days;

    struct Position {
        uint256 amount;
        uint256 lockMonths;
        uint256 lockTime;
        uint256 weight;
    }

    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => uint256) public positionCount;
    mapping(address => uint256) public totalWeightOf;
    mapping(address => uint256[]) internal activePositions; // Track active position IDs
    mapping(address => mapping(uint256 => uint256)) internal positionIndex; // positionId => index in activePositions

    uint256 public totalLocked;
    uint256 public totalSystemWeight;

    // User tracking for total vested weight calculation
    address[] public allUsers;
    mapping(address => bool) public isUser;

    event Locked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 lockMonths, uint256 weight);
    event Redeemed(address indexed user, uint256 indexed positionId, uint256 amount);

    constructor(address _tbtc, address _redemptionEngine) {
        if (_tbtc == address(0) || _redemptionEngine == address(0)) revert InvalidAmount();
        TBTC = _tbtc;
        redemptionEngine = _redemptionEngine;
    }

    function lock(uint256 amount, uint256 lockMonths) external returns (uint256 positionId) {
        if (amount == 0) revert InvalidAmount();
        if (lockMonths == 0) revert InvalidDuration();

        // Track new user
        if (!isUser[msg.sender]) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
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

    function redeem(address user, uint256 positionId) external {
        if (msg.sender != redemptionEngine) revert Unauthorized();

        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (block.timestamp < pos.lockTime + (pos.lockMonths * 30 days)) revert PositionLocked();

        delete positions[user][positionId];
        totalWeightOf[user] -= pos.weight;
        totalLocked -= pos.amount;
        totalSystemWeight -= pos.weight;

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

    function getPositionVestedWeight(address user, uint256 positionId) public view returns (uint256) {
        Position memory pos = positions[user][positionId];
        if (pos.amount == 0) return 0;

        uint256 elapsed = block.timestamp - pos.lockTime;
        if (elapsed < WEIGHT_WARMUP_PERIOD) return 0;
        if (elapsed >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD) return pos.weight;

        return (pos.weight * (elapsed - WEIGHT_WARMUP_PERIOD)) / WEIGHT_VESTING_PERIOD;
    }

    /// @notice Get vested weight for a user (only iterates active positions - gas efficient)
    function getVestedWeight(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] memory active = activePositions[user];
        for (uint256 i = 0; i < active.length; i++) {
            total += getPositionVestedWeight(user, active[i]);
        }
        return total;
    }

    /// @notice Get total vested weight across ALL users (for accurate epoch snapshots)
    /// @dev Gas intensive - only call from view functions or when necessary
    function getTotalVestedWeight() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < allUsers.length; i++) {
            address user = allUsers[i];
            uint256[] memory active = activePositions[user];
            for (uint256 j = 0; j < active.length; j++) {
                total += getPositionVestedWeight(user, active[j]);
            }
        }
        return total;
    }

    function getPosition(address user, uint256 positionId) external view returns (uint256, uint256, uint256, uint256) {
        Position memory pos = positions[user][positionId];
        return (pos.amount, pos.lockMonths, pos.lockTime + (pos.lockMonths * 30 days), pos.weight);
    }

    function calculateWeight(uint256 amount, uint256 lockMonths) public pure returns (uint256) {
        uint256 months = lockMonths > MAX_WEIGHT_MONTHS ? MAX_WEIGHT_MONTHS : lockMonths;
        return (amount * (WEIGHT_BASE + (months * WEIGHT_PER_MONTH))) / WEIGHT_BASE;
    }

    function isUnlocked(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        return pos.amount > 0 && block.timestamp >= pos.lockTime + (pos.lockMonths * 30 days);
    }

    function isWeightFullyVested(address user, uint256 positionId) external view returns (bool) {
        Position memory pos = positions[user][positionId];
        return pos.amount > 0 && block.timestamp - pos.lockTime >= WEIGHT_WARMUP_PERIOD + WEIGHT_VESTING_PERIOD;
    }

    function getTotalLocked() external view returns (uint256) { return totalLocked; }
    function getUserPositionCount(address user) external view returns (uint256) { return positionCount[user]; }
    function getActivePositionCount(address user) external view returns (uint256) { return activePositions[user].length; }
    function getActivePositions(address user) external view returns (uint256[] memory) { return activePositions[user]; }
    function getTotalUsers() external view returns (uint256) { return allUsers.length; }
}
