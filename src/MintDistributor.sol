// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDMDToken} from "./interfaces/IDMDToken.sol";
import {IBTCReserveVault} from "./interfaces/IBTCReserveVault.sol";
import {IEmissionScheduler} from "./interfaces/IEmissionScheduler.sol";

/// @title MintDistributor - Distributes DMD emissions by BTC lock weight
/// @author DMD Protocol Team
/// @notice Epoch-based distribution of DMD tokens proportional to tBTC lock weight
/// @dev Fully decentralized, uses vested weights consistently, supports epoch catch-up
/// @dev v1.8.9 - Security fixes: snapshot-based claims, emission caps, reentrancy protection
contract MintDistributor {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NoWeight();
    error NoEmissionsAvailable();
    error EpochNotFinalized();
    error InvalidEpoch();
    error InvalidAddress();
    error UserNotEligible();
    error SlippageExceeded();
    error ReentrancyGuard();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of each epoch (7 days)
    uint256 public constant EPOCH_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice DMD token contract
    IDMDToken public immutable DMD_TOKEN;
    /// @notice BTC Reserve Vault contract
    IBTCReserveVault public immutable VAULT;
    /// @notice Emission Scheduler contract
    IEmissionScheduler public immutable SCHEDULER;
    /// @notice Timestamp when distribution started
    uint256 public immutable DISTRIBUTION_START_TIME;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Data for each epoch
    /// @param totalEmission Total DMD emitted this epoch
    /// @param snapshotWeight Total vested weight at finalization
    /// @param finalized Whether epoch has been finalized
    /// @param totalMinted Total DMD actually minted from this epoch (for cap enforcement)
    /// @param finalizationTime Timestamp when epoch was finalized
    struct EpochData {
        uint256 totalEmission;
        uint256 snapshotWeight;
        bool finalized;
        uint256 totalMinted;
        uint256 finalizationTime;
    }

    /// @notice Snapshot of user's position weights at a specific epoch
    /// @param totalWeight Total vested weight of user at snapshot time
    /// @param positionWeights Weight of each position at snapshot time
    /// @param positionIds Position IDs that were active at snapshot time
    /// @param snapshotted Whether user has been snapshotted for this epoch
    struct UserEpochSnapshot {
        uint256 totalWeight;
        mapping(uint256 => uint256) positionWeights;
        uint256[] positionIds;
        bool snapshotted;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    /// @notice Next epoch ID to finalize (enables sequential catch-up)
    uint256 public nextEpochToFinalize;

    /// @notice Epoch data by epoch ID
    mapping(uint256 => EpochData) public epochs;

    /// @notice User weight snapshots: epochId => user => snapshot data
    mapping(uint256 => mapping(address => UserEpochSnapshot)) internal userSnapshots;

    /// @notice Legacy user weight snapshots for backward compatibility
    mapping(uint256 => mapping(address => uint256)) public userWeightSnapshot;

    /// @notice Claim status: epochId => user => claimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Total DMD minted per position: user => positionId => totalDmd
    mapping(address => mapping(uint256 => uint256)) public positionDmdMinted;

    /// @notice User's first lock time (for eligibility check)
    mapping(address => uint256) public userFirstLockTime;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an epoch is finalized
    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight, uint256 finalizationTime);
    /// @notice Emitted when user claims DMD for an epoch
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);
    /// @notice Emitted when user weight is snapshotted
    event WeightSnapshotted(uint256 indexed epochId, address indexed user, uint256 weight);
    /// @notice Emitted when user registers their first lock time
    event UserFirstLockRegistered(address indexed user, uint256 lockTime);
    /// @notice Emitted when position DMD minted tracking is cleared
    event PositionDmdMintedCleared(address indexed user, uint256 indexed positionId);

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

    /// @notice Initialize distributor with required contracts
    /// @param _dmdToken DMD token address
    /// @param _vault BTC Reserve Vault address
    /// @param _scheduler Emission Scheduler address
    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault, IEmissionScheduler _scheduler) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0) || address(_scheduler) == address(0)) {
            revert InvalidAddress();
        }
        DMD_TOKEN = _dmdToken;
        VAULT = _vault;
        SCHEDULER = _scheduler;
        DISTRIBUTION_START_TIME = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register user's first lock time (called when user first locks)
    /// @dev This should be called by the vault when a user first locks
    /// @dev For existing users, they can self-register by calling this
    /// @param user User address to register
    function registerUserFirstLock(address user) external {
        if (userFirstLockTime[user] != 0) return; // Already registered

        // Verify user actually has positions
        if (VAULT.getActivePositionCount(user) == 0) revert UserNotEligible();

        userFirstLockTime[user] = block.timestamp;
        emit UserFirstLockRegistered(user, block.timestamp);
    }

    /// @notice Finalize the next pending epoch
    /// @dev Uses getTotalVestedWeight() for consistent weight calculation
    /// @dev Permissionless - anyone can call
    /// @dev SECURITY FIX: Reverts if total vested weight is zero (prevents DoS)
    function finalizeEpoch() external nonReentrant {
        uint256 currentEpoch = getCurrentEpoch();
        if (currentEpoch == 0) revert InvalidEpoch();
        if (nextEpochToFinalize >= currentEpoch) revert InvalidEpoch();

        uint256 epochToFinalize = nextEpochToFinalize;

        // CRITICAL FIX: Check weight BEFORE claiming emissions to prevent loss
        // If we claim emissions then discover zero weight, those emissions are lost forever
        uint256 vestedWeight = _calculateFreshTotalVestedWeight();
        if (vestedWeight == 0) {
            nextEpochToFinalize = epochToFinalize + 1;
            return; // Skip epoch without claiming emissions - they accumulate for next claim
        }

        // Now safe to claim emissions (we know weight > 0)
        uint256 emission = SCHEDULER.claimEmission();
        if (emission == 0) revert NoEmissionsAvailable();

        epochs[epochToFinalize] = EpochData({
            totalEmission: emission,
            snapshotWeight: vestedWeight,
            finalized: true,
            totalMinted: 0,
            finalizationTime: block.timestamp
        });
        nextEpochToFinalize = epochToFinalize + 1;

        emit EpochFinalized(epochToFinalize, emission, vestedWeight, block.timestamp);
    }

    /// @notice Finalize multiple epochs at once (catch up on missed epochs)
    /// @dev SECURITY FIX: Skips epochs with zero weight instead of storing them
    /// @param count Maximum number of epochs to finalize
    function finalizeMultipleEpochs(uint256 count) external nonReentrant {
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = 0; i < count;) {
            if (nextEpochToFinalize >= currentEpoch) break;

            // CRITICAL FIX: Check weight BEFORE claiming emissions
            uint256 vestedWeight = _calculateFreshTotalVestedWeight();
            if (vestedWeight == 0) {
                nextEpochToFinalize++;
                unchecked { ++i; }
                continue; // Skip without claiming - emissions accumulate
            }

            // Now safe to claim (weight > 0)
            uint256 emission = SCHEDULER.claimEmission();
            if (emission == 0) break;

            epochs[nextEpochToFinalize] = EpochData({
                totalEmission: emission,
                snapshotWeight: vestedWeight,
                finalized: true,
                totalMinted: 0,
                finalizationTime: block.timestamp
            });

            emit EpochFinalized(nextEpochToFinalize, emission, vestedWeight, block.timestamp);
            nextEpochToFinalize++;
            unchecked { ++i; }
        }
    }

    /// @notice Snapshot your own weight for an epoch (MUST be called before claiming)
    /// @dev This creates an immutable snapshot of user's weight at call time
    /// @dev Only the user themselves can snapshot their weight (prevents griefing)
    /// @param epochId Epoch to snapshot for
    function snapshotMyWeight(uint256 epochId) external {
        _snapshotUserWeight(epochId, msg.sender);
    }

    /// @notice Snapshot user's weight - only callable by user themselves or vault
    /// @dev Restricts who can snapshot to prevent griefing attacks
    /// @param epochId Epoch to snapshot for
    /// @param user User address to snapshot
    function snapshotUserWeight(uint256 epochId, address user) external {
        // SECURITY FIX: Only user themselves or vault can snapshot
        // This prevents griefing where attacker snapshots user at suboptimal time
        if (msg.sender != user && msg.sender != address(VAULT)) {
            revert Unauthorized();
        }
        _snapshotUserWeight(epochId, user);
    }

    /// @notice Internal function to snapshot user weight
    /// @param epochId Epoch to snapshot for
    /// @param user User address to snapshot
    function _snapshotUserWeight(uint256 epochId, address user) internal {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) revert EpochNotFinalized();

        UserEpochSnapshot storage snapshot = userSnapshots[epochId][user];
        if (snapshot.snapshotted) return; // Already snapshotted

        // SECURITY FIX #1: User must have locked BEFORE epoch was finalized
        uint256 firstLock = userFirstLockTime[user];
        if (firstLock == 0 || firstLock >= epoch.finalizationTime) {
            revert UserNotEligible();
        }

        // Get current vested weight
        uint256 weight = VAULT.getVestedWeight(user);
        if (weight == 0) return; // No weight to snapshot

        // SECURITY FIX #2: Store position-level weights for accurate distribution
        uint256[] memory positions = VAULT.getActivePositions(user);
        uint256 len = positions.length;

        snapshot.totalWeight = weight;
        snapshot.snapshotted = true;

        for (uint256 i = 0; i < len;) {
            uint256 posId = positions[i];
            uint256 posWeight = VAULT.getPositionVestedWeight(user, posId);
            if (posWeight > 0) {
                snapshot.positionWeights[posId] = posWeight;
                snapshot.positionIds.push(posId);
            }
            unchecked { ++i; }
        }

        // Also update legacy mapping for backward compatibility
        userWeightSnapshot[epochId][user] = weight;

        emit WeightSnapshotted(epochId, user, weight);
    }

    /// @notice Claim DMD for a single epoch
    /// @dev User MUST have snapshotted their weight first
    /// @param epochId Epoch to claim from
    function claim(uint256 epochId) external nonReentrant {
        _claim(epochId, 0);
    }

    /// @notice Claim DMD for a single epoch with slippage protection
    /// @param epochId Epoch to claim from
    /// @param minAmount Minimum DMD expected (reverts if less)
    function claimWithSlippage(uint256 epochId, uint256 minAmount) external nonReentrant {
        _claim(epochId, minAmount);
    }

    /// @notice Claim DMD for multiple epochs at once
    /// @dev User MUST have snapshotted their weight for each epoch first
    /// @param epochIds Array of epoch IDs to claim from
    function claimMultiple(uint256[] calldata epochIds) external nonReentrant {
        uint256 len = epochIds.length;
        for (uint256 i = 0; i < len;) {
            _claimInternal(epochIds[i], 0);
            unchecked { ++i; }
        }
    }

    /// @notice Claim DMD for multiple epochs with slippage protection
    /// @param epochIds Array of epoch IDs to claim from
    /// @param minAmounts Minimum DMD expected per epoch
    function claimMultipleWithSlippage(uint256[] calldata epochIds, uint256[] calldata minAmounts) external nonReentrant {
        uint256 len = epochIds.length;
        for (uint256 i = 0; i < len;) {
            uint256 minAmount = i < minAmounts.length ? minAmounts[i] : 0;
            _claimInternal(epochIds[i], minAmount);
            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current epoch number
    /// @return Current epoch (0-indexed)
    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - DISTRIBUTION_START_TIME) / EPOCH_DURATION;
    }

    /// @notice Get number of epochs pending finalization
    /// @return Number of epochs that can be finalized
    function getPendingEpochCount() external view returns (uint256) {
        uint256 current = getCurrentEpoch();
        return current > nextEpochToFinalize ? current - nextEpochToFinalize : 0;
    }

    /// @notice Get claimable DMD amount for user in epoch
    /// @dev Returns 0 if user hasn't snapshotted or is ineligible
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return Claimable DMD amount
    function getClaimableAmount(address user, uint256 epochId) external view returns (uint256) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized || claimed[epochId][user] || epoch.snapshotWeight == 0) return 0;

        UserEpochSnapshot storage snapshot = userSnapshots[epochId][user];

        // Must have snapshot
        if (!snapshot.snapshotted) return 0;
        if (snapshot.totalWeight == 0) return 0;

        uint256 share = (epoch.totalEmission * snapshot.totalWeight) / epoch.snapshotWeight;

        // SECURITY FIX #3: Cap at remaining emission
        uint256 remaining = epoch.totalEmission > epoch.totalMinted ?
            epoch.totalEmission - epoch.totalMinted : 0;

        return share > remaining ? remaining : share;
    }

    /// @notice Check if user has claimed for epoch
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return True if claimed
    function hasClaimed(address user, uint256 epochId) external view returns (bool) {
        return claimed[epochId][user];
    }

    /// @notice Check if user has snapshotted for epoch
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return True if snapshotted
    function hasSnapshotted(address user, uint256 epochId) external view returns (bool) {
        return userSnapshots[epochId][user].snapshotted;
    }

    /// @notice Check if user is eligible for an epoch
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return True if user locked before epoch finalization
    function isEligibleForEpoch(address user, uint256 epochId) external view returns (bool) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) return false;

        uint256 firstLock = userFirstLockTime[user];
        return firstLock != 0 && firstLock < epoch.finalizationTime;
    }

    /// @notice Get epoch data
    /// @param epochId Epoch to query
    /// @return totalEmission Total emission for epoch
    /// @return snapshotWeight Total weight snapshot
    /// @return finalized Whether epoch is finalized
    function getEpochData(uint256 epochId) external view returns (uint256 totalEmission, uint256 snapshotWeight, bool finalized) {
        EpochData storage e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized);
    }

    /// @notice Get extended epoch data including minted amount
    /// @param epochId Epoch to query
    /// @return totalEmission Total emission for epoch
    /// @return snapshotWeight Total weight snapshot
    /// @return finalized Whether epoch is finalized
    /// @return totalMinted Total DMD minted from this epoch
    /// @return finalizationTime When epoch was finalized
    function getEpochDataExtended(uint256 epochId) external view returns (
        uint256 totalEmission,
        uint256 snapshotWeight,
        bool finalized,
        uint256 totalMinted,
        uint256 finalizationTime
    ) {
        EpochData storage e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized, e.totalMinted, e.finalizationTime);
    }

    /// @notice Get seconds until next epoch starts
    /// @return Seconds remaining (0 if epoch already started)
    function timeUntilNextEpoch() external view returns (uint256) {
        uint256 nextStart = DISTRIBUTION_START_TIME + ((getCurrentEpoch() + 1) * EPOCH_DURATION);
        return block.timestamp >= nextStart ? 0 : nextStart - block.timestamp;
    }

    /// @notice Get next epoch ID to be finalized
    /// @return Next epoch to finalize
    function getNextEpochToFinalize() external view returns (uint256) {
        return nextEpochToFinalize;
    }

    /// @notice Get total DMD minted for a specific position
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return Total DMD minted to this position
    function getPositionDmdMinted(address user, uint256 positionId) external view returns (uint256) {
        return positionDmdMinted[user][positionId];
    }

    /// @notice Clear DMD minted tracking for a position (called after redemption)
    /// @dev SECURITY FIX: Prevents position ID reuse from accumulating old DMD debts
    /// @dev Only callable by the vault (which is called by RedemptionEngine)
    /// @param user Position owner
    /// @param positionId Position ID to clear
    function clearPositionDmdMinted(address user, uint256 positionId) external {
        // Only the vault can call this (triggered during redeem flow)
        if (msg.sender != address(VAULT)) revert Unauthorized();
        delete positionDmdMinted[user][positionId];
        emit PositionDmdMintedCleared(user, positionId);
    }

    /// @notice Get user's snapshotted weight for an epoch
    /// @param user User address
    /// @param epochId Epoch ID
    /// @return User's snapshotted weight
    function getUserSnapshotWeight(address user, uint256 epochId) external view returns (uint256) {
        return userSnapshots[epochId][user].totalWeight;
    }

    /// @notice Get user's snapshotted position weight for an epoch
    /// @param user User address
    /// @param epochId Epoch ID
    /// @param positionId Position ID
    /// @return Position's snapshotted weight
    function getUserPositionSnapshotWeight(address user, uint256 epochId, uint256 positionId) external view returns (uint256) {
        return userSnapshots[epochId][user].positionWeights[positionId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal claim with slippage check
    function _claim(uint256 epochId, uint256 minAmount) internal {
        uint256 amount = _claimInternal(epochId, minAmount);
        if (amount == 0) revert NoWeight();
    }

    /// @notice Internal claim logic
    /// @return amount The amount claimed (0 if skipped)
    function _claimInternal(uint256 epochId, uint256 minAmount) internal returns (uint256 amount) {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) return 0;
        if (claimed[epochId][msg.sender]) return 0;
        if (epoch.snapshotWeight == 0) return 0;

        UserEpochSnapshot storage snapshot = userSnapshots[epochId][msg.sender];

        // SECURITY FIX #1: Must have snapshot (prevents late-joiner attack)
        if (!snapshot.snapshotted) revert UserNotEligible();
        if (snapshot.totalWeight == 0) return 0;

        // Calculate share based on SNAPSHOTTED weight (not current weight)
        uint256 share = (epoch.totalEmission * snapshot.totalWeight) / epoch.snapshotWeight;

        // SECURITY FIX #3: Cap at remaining emission to prevent over-minting
        uint256 remaining = epoch.totalEmission > epoch.totalMinted ?
            epoch.totalEmission - epoch.totalMinted : 0;

        if (share > remaining) {
            share = remaining;
        }

        if (share == 0) return 0;

        // SECURITY FIX #8: Slippage protection
        if (minAmount > 0 && share < minAmount) revert SlippageExceeded();

        // Mark claimed and update minted tracking BEFORE external calls
        claimed[epochId][msg.sender] = true;
        epoch.totalMinted += share;

        // Mint DMD
        DMD_TOKEN.mint(msg.sender, share);

        // SECURITY FIX #2: Distribute to positions using SNAPSHOTTED weights
        _distributeToPositionsFromSnapshot(msg.sender, share, snapshot);

        emit Claimed(msg.sender, epochId, share);
        return share;
    }

    /// @notice Distribute DMD to positions using snapshotted weights
    /// @dev Uses stored snapshot weights, not current weights
    /// @param user User address
    /// @param totalDmd Total DMD to distribute
    /// @param snapshot User's epoch snapshot
    function _distributeToPositionsFromSnapshot(
        address user,
        uint256 totalDmd,
        UserEpochSnapshot storage snapshot
    ) internal {
        if (snapshot.totalWeight == 0 || totalDmd == 0) return;

        uint256 len = snapshot.positionIds.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < len;) {
            uint256 posId = snapshot.positionIds[i];
            uint256 posWeight = snapshot.positionWeights[posId];

            if (posWeight > 0) {
                uint256 posShare;
                if (i == len - 1) {
                    // Last position gets remainder to avoid rounding dust
                    posShare = totalDmd - distributed;
                } else {
                    posShare = (totalDmd * posWeight) / snapshot.totalWeight;
                }
                positionDmdMinted[user][posId] += posShare;
                distributed += posShare;
            }
            unchecked { ++i; }
        }
    }

    /// @notice Get fresh total vested weight from vault
    /// @dev Used during finalization to ensure accurate snapshot
    /// @return Total vested weight across all users
    function _calculateFreshTotalVestedWeight() internal view returns (uint256) {
        return VAULT.getTotalVestedWeight();
    }
}
