// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";
import "./interfaces/IEmissionScheduler.sol";

/// @title MintDistributor - Distributes DMD emissions by BTC lock weight
/// @dev Fully decentralized, epoch-based, uses vested weights consistently
/// @dev Supports epoch skip protection - can catch up on missed epochs
contract MintDistributor {
    error AlreadyClaimed();
    error NoWeight();
    error NoEmissionsAvailable();
    error EpochNotFinalized();
    error EpochAlreadyFinalized();
    error InvalidEpoch();
    error InvalidAddress();

    uint256 public constant EPOCH_DURATION = 7 days;

    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;
    IEmissionScheduler public immutable scheduler;
    uint256 public immutable distributionStartTime;

    // Track next epoch to finalize (supports catching up on missed epochs)
    uint256 public nextEpochToFinalize;

    struct EpochData {
        uint256 totalEmission;
        uint256 snapshotWeight; // Now uses vested weight for consistency
        bool finalized;
    }

    mapping(uint256 => EpochData) public epochs;
    mapping(uint256 => mapping(address => uint256)) public userWeightSnapshot;
    mapping(uint256 => mapping(address => bool)) public claimed;

    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault, IEmissionScheduler _scheduler) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0) || address(_scheduler) == address(0)) {
            revert InvalidAddress();
        }
        dmdToken = _dmdToken;
        vault = _vault;
        scheduler = _scheduler;
        distributionStartTime = block.timestamp;
        nextEpochToFinalize = 0;
    }

    /// @notice Finalize the next pending epoch (supports catching up on missed epochs)
    /// @dev Uses getTotalVestedWeight() for consistent weight calculation
    function finalizeEpoch() external {
        uint256 currentEpoch = getCurrentEpoch();

        // Must have at least one completable epoch
        if (currentEpoch == 0) revert InvalidEpoch();

        // Can only finalize epochs that have ended
        if (nextEpochToFinalize >= currentEpoch) revert InvalidEpoch();

        uint256 epochToFinalize = nextEpochToFinalize;

        // Claim emissions from scheduler
        uint256 emission = scheduler.claimEmission();
        if (emission == 0) revert NoEmissionsAvailable();

        // Use VESTED weight for consistent calculation (fixes weight inconsistency issue)
        uint256 vestedWeight = vault.getTotalVestedWeight();

        epochs[epochToFinalize] = EpochData(emission, vestedWeight, true);
        nextEpochToFinalize = epochToFinalize + 1;

        emit EpochFinalized(epochToFinalize, emission, vestedWeight);
    }

    /// @notice Finalize multiple epochs at once (catch up on missed epochs)
    /// @param count Number of epochs to finalize
    function finalizeMultipleEpochs(uint256 count) external {
        uint256 currentEpoch = getCurrentEpoch();

        for (uint256 i = 0; i < count; i++) {
            if (nextEpochToFinalize >= currentEpoch) break;

            uint256 emission = scheduler.claimEmission();
            if (emission == 0) break;

            uint256 vestedWeight = vault.getTotalVestedWeight();
            epochs[nextEpochToFinalize] = EpochData(emission, vestedWeight, true);

            emit EpochFinalized(nextEpochToFinalize, emission, vestedWeight);
            nextEpochToFinalize++;
        }
    }

    /// @notice Get number of epochs pending finalization
    function getPendingEpochCount() external view returns (uint256) {
        uint256 current = getCurrentEpoch();
        return current > nextEpochToFinalize ? current - nextEpochToFinalize : 0;
    }

    function snapshotUserWeight(uint256 epochId, address user) external {
        if (!epochs[epochId].finalized) revert EpochNotFinalized();
        if (userWeightSnapshot[epochId][user] == 0) {
            uint256 weight = vault.getVestedWeight(user);
            if (weight > 0) userWeightSnapshot[epochId][user] = weight;
        }
    }

    function claim(uint256 epochId) external {
        EpochData memory epoch = epochs[epochId];
        if (!epoch.finalized) revert EpochNotFinalized();
        if (claimed[epochId][msg.sender]) revert AlreadyClaimed();

        // Use vested weight (consistent with snapshot)
        uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
        if (userWeight == 0) userWeight = vault.getVestedWeight(msg.sender);
        if (userWeight == 0 || epoch.snapshotWeight == 0) revert NoWeight();

        claimed[epochId][msg.sender] = true;
        uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        dmdToken.mint(msg.sender, share);

        emit Claimed(msg.sender, epochId, share);
    }

    function claimMultiple(uint256[] calldata epochIds) external {
        for (uint256 i = 0; i < epochIds.length; i++) {
            uint256 epochId = epochIds[i];
            EpochData memory epoch = epochs[epochId];

            if (!epoch.finalized || claimed[epochId][msg.sender] || epoch.snapshotWeight == 0) continue;

            uint256 userWeight = userWeightSnapshot[epochId][msg.sender];
            if (userWeight == 0) userWeight = vault.getVestedWeight(msg.sender);
            if (userWeight == 0) continue;

            claimed[epochId][msg.sender] = true;
            uint256 share = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
            dmdToken.mint(msg.sender, share);
            emit Claimed(msg.sender, epochId, share);
        }
    }

    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - distributionStartTime) / EPOCH_DURATION;
    }

    function getClaimableAmount(address user, uint256 epochId) external view returns (uint256) {
        EpochData memory epoch = epochs[epochId];
        if (!epoch.finalized || claimed[epochId][user] || epoch.snapshotWeight == 0) return 0;

        uint256 userWeight = userWeightSnapshot[epochId][user];
        if (userWeight == 0) userWeight = vault.getVestedWeight(user);
        if (userWeight == 0) return 0;

        return (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
    }

    function hasClaimed(address user, uint256 epochId) external view returns (bool) { return claimed[epochId][user]; }

    function getEpochData(uint256 epochId) external view returns (uint256, uint256, bool) {
        EpochData memory e = epochs[epochId];
        return (e.totalEmission, e.snapshotWeight, e.finalized);
    }

    function timeUntilNextEpoch() external view returns (uint256) {
        uint256 nextStart = distributionStartTime + ((getCurrentEpoch() + 1) * EPOCH_DURATION);
        return block.timestamp >= nextStart ? 0 : nextStart - block.timestamp;
    }

    function getNextEpochToFinalize() external view returns (uint256) { return nextEpochToFinalize; }
}
