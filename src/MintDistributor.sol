// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";
import "./interfaces/IEmissionScheduler.sol";

/**
 * @title MintDistributor
 * @notice Distributes DMD emissions proportionally based on BTC lock weights
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev Epoch-based claiming with weight-proportional allocation
 * @dev Uses vested weights to prevent flash loan attacks
 * @dev Distribution starts automatically at deployment
 */
contract MintDistributor {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyClaimed();
    error NoWeight();
    error NoEmissionsAvailable();
    error EpochNotFinalized();
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant EPOCH_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;
    IEmissionScheduler public immutable scheduler;

    /// @notice Timestamp when distribution started (set at deployment)
    uint256 public immutable distributionStartTime;

    /// @notice Last epoch that was finalized
    uint256 public lastClaimEpoch;

    // Epoch tracking
    struct EpochData {
        uint256 totalEmission;      // Total DMD emitted this epoch
        uint256 snapshotWeight;     // Total system weight snapshot
        bool finalized;             // Whether epoch is closed for claims
    }

    mapping(uint256 => EpochData) public epochs;

    // User weight snapshots: epochId => user => weight at finalization
    mapping(uint256 => mapping(address => uint256)) public userWeightSnapshot;

    // User claims: epochId => user => claimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DistributionStarted(uint256 startTime);
    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);
    event WeightSnapshotted(uint256 indexed epochId, address indexed user, uint256 weight);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy and automatically start distribution
     * @param _dmdToken Address of DMD token contract
     * @param _vault Address of BTCReserveVault contract
     * @param _scheduler Address of EmissionScheduler contract
     * @dev Distribution begins immediately - no owner needed
     */
    constructor(
        IDMDToken _dmdToken,
        IBTCReserveVault _vault,
        IEmissionScheduler _scheduler
    ) {
        if (
            address(_dmdToken) == address(0) ||
            address(_vault) == address(0) ||
            address(_scheduler) == address(0)
        ) {
            revert InvalidAddress();
        }

        dmdToken = _dmdToken;
        vault = _vault;
        scheduler = _scheduler;
        distributionStartTime = block.timestamp;

        emit DistributionStarted(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          EPOCH MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalize current epoch and snapshot emissions
     * @dev Callable by anyone after epoch end, claims emissions from scheduler
     * @dev Permissionless - anyone can trigger epoch finalization
     */
    function finalizeEpoch() external {
        uint256 currentEpoch = getCurrentEpoch();

        // Can only finalize past epochs
        if (currentEpoch == 0) revert EpochNotFinalized();

        uint256 epochToFinalize = currentEpoch - 1;

        // Check if already finalized
        if (epochs[epochToFinalize].finalized) revert EpochNotFinalized();

        // Claim emissions from scheduler
        uint256 emission = scheduler.claimEmission();
        if (emission == 0) revert NoEmissionsAvailable();

        // Snapshot system weight at finalization
        uint256 systemWeight = vault.totalSystemWeight();

        epochs[epochToFinalize] = EpochData({
            totalEmission: emission,
            snapshotWeight: systemWeight,
            finalized: true
        });

        lastClaimEpoch = epochToFinalize;

        emit EpochFinalized(epochToFinalize, emission, systemWeight);
    }

    /**
     * @notice Snapshot user's vested weight for a finalized epoch
     * @param epochId Epoch to snapshot for
     * @dev Can be called by anyone for any user - creates snapshot for fair claiming
     * @dev Must be called before claiming to lock in weight at finalization time
     */
    function snapshotUserWeight(uint256 epochId, address user) external {
        EpochData memory epoch = epochs[epochId];
        if (!epoch.finalized) revert EpochNotFinalized();

        // Only snapshot if not already done
        if (userWeightSnapshot[epochId][user] == 0) {
            uint256 weight = vault.getVestedWeight(user);
            if (weight > 0) {
                userWeightSnapshot[epochId][user] = weight;
                emit WeightSnapshotted(epochId, user, weight);
            }
        }
    }

    /**
     * @notice Batch snapshot multiple users for an epoch
     * @param epochId Epoch to snapshot for
     * @param users Array of user addresses
     */
    function snapshotMultipleUsers(uint256 epochId, address[] calldata users) external {
        EpochData memory epoch = epochs[epochId];
        if (!epoch.finalized) revert EpochNotFinalized();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (userWeightSnapshot[epochId][user] == 0) {
                uint256 weight = vault.getVestedWeight(user);
                if (weight > 0) {
                    userWeightSnapshot[epochId][user] = weight;
                    emit WeightSnapshotted(epochId, user, weight);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim DMD allocation for a finalized epoch
     * @param epochId Epoch to claim from
     * @dev Uses snapshotted weight if available, otherwise uses current vested weight
     */
    function claim(uint256 epochId) external {
        EpochData memory epoch = epochs[epochId];

        if (!epoch.finalized) revert EpochNotFinalized();
        if (claimed[epochId][msg.sender]) revert AlreadyClaimed();

        // Use snapshotted weight if available, otherwise use current vested weight
        uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
        if (userWeight == 0) {
            userWeight = vault.getVestedWeight(msg.sender);
        }

        if (userWeight == 0) revert NoWeight();
        if (epoch.snapshotWeight == 0) revert NoWeight();

        // Calculate proportional share
        uint256 userShare = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;

        claimed[epochId][msg.sender] = true;

        // Mint DMD to user
        dmdToken.mint(msg.sender, userShare);

        emit Claimed(msg.sender, epochId, userShare);
    }

    /**
     * @notice Batch claim multiple epochs
     * @param epochIds Array of epoch IDs to claim from
     */
    function claimMultiple(uint256[] calldata epochIds) external {
        for (uint256 i = 0; i < epochIds.length; i++) {
            uint256 epochId = epochIds[i];

            EpochData memory epoch = epochs[epochId];
            if (!epoch.finalized) continue;
            if (claimed[epochId][msg.sender]) continue;
            if (epoch.snapshotWeight == 0) continue;

            // Use snapshotted weight if available
            uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
            if (userWeight == 0) {
                userWeight = vault.getVestedWeight(msg.sender);
            }

            if (userWeight == 0) continue;

            uint256 userShare = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;

            claimed[epochId][msg.sender] = true;
            dmdToken.mint(msg.sender, userShare);

            emit Claimed(msg.sender, epochId, userShare);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current epoch number
     */
    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - distributionStartTime) / EPOCH_DURATION;
    }

    /**
     * @notice Calculate claimable amount for user in specific epoch
     * @param user User address
     * @param epochId Epoch to check
     * @return Claimable amount (0 if already claimed or no weight)
     */
    function getClaimableAmount(address user, uint256 epochId)
        external
        view
        returns (uint256)
    {
        EpochData memory epoch = epochs[epochId];

        if (!epoch.finalized) return 0;
        if (claimed[epochId][user]) return 0;
        if (epoch.snapshotWeight == 0) return 0;

        // Use snapshotted weight if available
        uint256 userWeight = userWeightSnapshot[epochId][user];
        if (userWeight == 0) {
            userWeight = vault.getVestedWeight(user);
        }

        if (userWeight == 0) return 0;

        return (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
    }

    /**
     * @notice Check if user has claimed for specific epoch
     */
    function hasClaimed(address user, uint256 epochId) external view returns (bool) {
        return claimed[epochId][user];
    }

    /**
     * @notice Get user's snapshotted weight for an epoch
     */
    function getUserSnapshot(address user, uint256 epochId) external view returns (uint256) {
        return userWeightSnapshot[epochId][user];
    }

    /**
     * @notice Get epoch details
     */
    function getEpochData(uint256 epochId)
        external
        view
        returns (
            uint256 totalEmission,
            uint256 snapshotWeight,
            bool finalized
        )
    {
        EpochData memory epoch = epochs[epochId];
        return (epoch.totalEmission, epoch.snapshotWeight, epoch.finalized);
    }

    /**
     * @notice Calculate total claimable across multiple epochs
     */
    function getTotalClaimable(address user, uint256[] calldata epochIds)
        external
        view
        returns (uint256 total)
    {
        for (uint256 i = 0; i < epochIds.length; i++) {
            uint256 epochId = epochIds[i];
            EpochData memory epoch = epochs[epochId];

            if (!epoch.finalized || claimed[epochId][user] || epoch.snapshotWeight == 0) {
                continue;
            }

            uint256 userWeight = userWeightSnapshot[epochId][user];
            if (userWeight == 0) {
                userWeight = vault.getVestedWeight(user);
            }

            if (userWeight == 0) continue;

            total += (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        }
    }

    /**
     * @notice Get time until next epoch
     */
    function timeUntilNextEpoch() external view returns (uint256) {
        uint256 currentEpoch = getCurrentEpoch();
        uint256 nextEpochStart = distributionStartTime + ((currentEpoch + 1) * EPOCH_DURATION);
        if (block.timestamp >= nextEpochStart) return 0;
        return nextEpochStart - block.timestamp;
    }
}
