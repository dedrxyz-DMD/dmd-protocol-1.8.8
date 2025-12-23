// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";
import "./interfaces/IEmissionScheduler.sol";

/// @title MintDistributor - Distributes DMD emissions by BTC lock weight
/// @author DMD Protocol Team
/// @notice Epoch-based distribution of DMD tokens proportional to tBTC lock weight
/// @dev Fully decentralized, uses vested weights consistently, supports epoch catch-up
contract MintDistributor {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyClaimed();
    error NoWeight();
    error NoEmissionsAvailable();
    error EpochNotFinalized();
    error EpochAlreadyFinalized();
    error InvalidEpoch();
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of each epoch (7 days)
    uint256 public constant EPOCH_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice DMD token contract
    IDMDToken public immutable dmdToken;
    /// @notice BTC Reserve Vault contract
    IBTCReserveVault public immutable vault;
    /// @notice Emission Scheduler contract
    IEmissionScheduler public immutable scheduler;
    /// @notice Timestamp when distribution started
    uint256 public immutable distributionStartTime;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Data for each epoch
    /// @param totalEmission Total DMD emitted this epoch
    /// @param snapshotWeight Total vested weight at finalization
    /// @param finalized Whether epoch has been finalized
    struct EpochData {
        uint256 totalEmission;
        uint256 snapshotWeight;
        bool finalized;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Next epoch ID to finalize (enables sequential catch-up)
    uint256 public nextEpochToFinalize;

    /// @notice Epoch data by epoch ID
    mapping(uint256 => EpochData) public epochs;
    /// @notice User weight snapshots: epochId => user => weight
    mapping(uint256 => mapping(address => uint256)) public userWeightSnapshot;
    /// @notice Claim status: epochId => user => claimed
    mapping(uint256 => mapping(address => bool)) public claimed;
    /// @notice Total DMD minted per position: user => positionId => totalDMD
    mapping(address => mapping(uint256 => uint256)) public positionDMDMinted;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an epoch is finalized
    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight);
    /// @notice Emitted when user claims DMD for an epoch
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);
    /// @notice Emitted when user weight is snapshotted
    event WeightSnapshotted(uint256 indexed epochId, address indexed user, uint256 weight);

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
        dmdToken = _dmdToken;
        vault = _vault;
        scheduler = _scheduler;
        distributionStartTime = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Finalize the next pending epoch
    /// @dev Uses getTotalVestedWeight() for consistent weight calculation
    /// @dev Permissionless - anyone can call
    function finalizeEpoch() external {
        uint256 currentEpoch = getCurrentEpoch();
        if (currentEpoch == 0) revert InvalidEpoch();
        if (nextEpochToFinalize >= currentEpoch) revert InvalidEpoch();

        uint256 epochToFinalize = nextEpochToFinalize;
        uint256 emission = scheduler.claimEmission();
        if (emission == 0) revert NoEmissionsAvailable();

        uint256 vestedWeight = vault.getTotalVestedWeight();
        epochs[epochToFinalize] = EpochData(emission, vestedWeight, true);
        nextEpochToFinalize = epochToFinalize + 1;

        emit EpochFinalized(epochToFinalize, emission, vestedWeight);
    }

    /// @notice Finalize multiple epochs at once (catch up on missed epochs)
    /// @param count Maximum number of epochs to finalize
    function finalizeMultipleEpochs(uint256 count) external {
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = 0; i < count;) {
            if (nextEpochToFinalize >= currentEpoch) break;

            uint256 emission = scheduler.claimEmission();
            if (emission == 0) break;

            uint256 vestedWeight = vault.getTotalVestedWeight();
            epochs[nextEpochToFinalize] = EpochData(emission, vestedWeight, true);

            emit EpochFinalized(nextEpochToFinalize, emission, vestedWeight);
            nextEpochToFinalize++;
            unchecked { ++i; }
        }
    }

    /// @notice Snapshot user's current weight for an epoch
    /// @param epochId Epoch to snapshot for
    /// @param user User address to snapshot
    function snapshotUserWeight(uint256 epochId, address user) external {
        if (!epochs[epochId].finalized) revert EpochNotFinalized();
        if (userWeightSnapshot[epochId][user] == 0) {
            uint256 weight = vault.getVestedWeight(user);
            if (weight > 0) {
                userWeightSnapshot[epochId][user] = weight;
                emit WeightSnapshotted(epochId, user, weight);
            }
        }
    }

    /// @notice Claim DMD for a single epoch
    /// @dev Distributes DMD proportionally to each active position based on weight
    /// @param epochId Epoch to claim from
    function claim(uint256 epochId) external {
        EpochData storage epoch = epochs[epochId];
        if (!epoch.finalized) revert EpochNotFinalized();
        if (claimed[epochId][msg.sender]) revert AlreadyClaimed();

        uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
        if (userWeight == 0) userWeight = vault.getVestedWeight(msg.sender);
        if (userWeight == 0 || epoch.snapshotWeight == 0) revert NoWeight();

        claimed[epochId][msg.sender] = true;
        uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        dmdToken.mint(msg.sender, share);

        // Track DMD per position proportionally
        _distributeToPositions(msg.sender, share, userWeight);

        emit Claimed(msg.sender, epochId, share);
    }

    /// @notice Claim DMD for multiple epochs at once
    /// @dev Distributes DMD proportionally to each active position based on weight
    /// @param epochIds Array of epoch IDs to claim from
    function claimMultiple(uint256[] calldata epochIds) external {
        uint256 len = epochIds.length;
        for (uint256 i = 0; i < len;) {
            uint256 epochId = epochIds[i];
            EpochData storage epoch = epochs[epochId];

            if (!epoch.finalized || claimed[epochId][msg.sender] || epoch.snapshotWeight == 0) {
                unchecked { ++i; }
                continue;
            }

            uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
            if (userWeight == 0) userWeight = vault.getVestedWeight(msg.sender);
            if (userWeight == 0) {
                unchecked { ++i; }
                continue;
            }

            claimed[epochId][msg.sender] = true;
            uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
            dmdToken.mint(msg.sender, share);

            // Track DMD per position proportionally
            _distributeToPositions(msg.sender, share, userWeight);

            emit Claimed(msg.sender, epochId, share);
            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current epoch number
    /// @return Current epoch (0-indexed)
    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - distributionStartTime) / EPOCH_DURATION;
    }

    /// @notice Get number of epochs pending finalization
    /// @return Number of epochs that can be finalized
    function getPendingEpochCount() external view returns (uint256) {
        uint256 current = getCurrentEpoch();
        return current > nextEpochToFinalize ? current - nextEpochToFinalize : 0;
    }

    /// @notice Get claimable DMD amount for user in epoch
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return Claimable DMD amount
    function getClaimableAmount(address user, uint256 epochId) external view returns (uint256) {
        EpochData memory epoch = epochs[epochId];
        if (!epoch.finalized || claimed[epochId][user] || epoch.snapshotWeight == 0) return 0;

        uint256 userWeight = userWeightSnapshot[epochId][user];
        if (userWeight == 0) userWeight = vault.getVestedWeight(user);
        if (userWeight == 0) return 0;

        return (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
    }

    /// @notice Check if user has claimed for epoch
    /// @param user User address
    /// @param epochId Epoch to check
    /// @return True if claimed
    function hasClaimed(address user, uint256 epochId) external view returns (bool) {
        return claimed[epochId][user];
    }

    /// @notice Get epoch data
    /// @param epochId Epoch to query
    /// @return totalEmission Total emission for epoch
    /// @return snapshotWeight Total weight snapshot
    /// @return finalized Whether epoch is finalized
    function getEpochData(uint256 epochId) external view returns (uint256 totalEmission, uint256 snapshotWeight, bool finalized) {
        EpochData memory e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized);
    }

    /// @notice Get seconds until next epoch starts
    /// @return Seconds remaining (0 if epoch already started)
    function timeUntilNextEpoch() external view returns (uint256) {
        uint256 nextStart = distributionStartTime + ((getCurrentEpoch() + 1) * EPOCH_DURATION);
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
    function getPositionDMDMinted(address user, uint256 positionId) external view returns (uint256) {
        return positionDMDMinted[user][positionId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Distribute DMD to positions proportionally based on their weights
    /// @param user User address
    /// @param totalDMD Total DMD to distribute
    /// @param totalUserWeight Total vested weight of user
    function _distributeToPositions(address user, uint256 totalDMD, uint256 totalUserWeight) internal {
        if (totalUserWeight == 0) return;

        uint256[] memory positions = vault.getActivePositions(user);
        uint256 len = positions.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < len;) {
            uint256 posId = positions[i];
            uint256 posWeight = vault.getPositionVestedWeight(user, posId);

            if (posWeight > 0) {
                uint256 posShare;
                if (i == len - 1) {
                    // Last position gets remainder to avoid rounding dust
                    posShare = totalDMD - distributed;
                } else {
                    posShare = (totalDMD * posWeight) / totalUserWeight;
                }
                positionDMDMinted[user][posId] += posShare;
                distributed += posShare;
            }
            unchecked { ++i; }
        }
    }
}
