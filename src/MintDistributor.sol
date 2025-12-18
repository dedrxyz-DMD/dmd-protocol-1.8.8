// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";
import "./interfaces/IEmissionScheduler.sol";

/**
 * @title MintDistributor
 * @notice Distributes DMD emissions proportionally based on BTC lock weights
 * @dev Epoch-based claiming with weight-proportional allocation
 */
contract MintDistributor {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error AlreadyClaimed();
    error NoWeight();
    error NoEmissionsAvailable();
    error EpochNotFinalized();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant EPOCH_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;
    IEmissionScheduler public immutable scheduler;

    uint256 public distributionStartTime;
    uint256 public lastClaimEpoch;

    // Epoch tracking
    struct EpochData {
        uint256 totalEmission;      // Total DMD emitted this epoch
        uint256 snapshotWeight;     // Total system weight snapshot
        bool finalized;             // Whether epoch is closed for claims
    }

    mapping(uint256 => EpochData) public epochs;
    
    // User claims: epochId => user => claimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    // epochId => total claimed so far
    mapping(uint256 => uint256) public claimedTotal;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DistributionStarted(uint256 startTime);
    event EpochFinalized(uint256 indexed epochId, uint256 totalEmission, uint256 snapshotWeight);
    event Claimed(address indexed user, uint256 indexed epochId, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        IDMDToken _dmdToken,
        IBTCReserveVault _vault,
        IEmissionScheduler _scheduler
    ) {
        if (
            _owner == address(0) || 
            address(_dmdToken) == address(0) ||
            address(_vault) == address(0) ||
            address(_scheduler) == address(0)
        ) {
            revert Unauthorized();
        }

        owner = _owner;
        dmdToken = _dmdToken;
        vault = _vault;
        scheduler = _scheduler;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Start distribution (one-time only, must align with EmissionScheduler)
     */
    function startDistribution() external {
        if (msg.sender != owner) revert Unauthorized();
        if (distributionStartTime != 0) revert Unauthorized();

        distributionStartTime = block.timestamp;
        emit DistributionStarted(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          EPOCH MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalize current epoch and snapshot emissions
     * @dev Callable by anyone after epoch end, claims emissions from scheduler
     */
    function finalizeEpoch() external {
        if (distributionStartTime == 0) revert Unauthorized();

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

    /*//////////////////////////////////////////////////////////////
                          CLAIMING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim DMD allocation for a finalized epoch
     * @param epochId Epoch to claim from
     * @dev Uses VESTED weight for flash loan protection
     */
    function claim(uint256 epochId) external {
        EpochData memory epoch = epochs[epochId];

        if (!epoch.finalized) revert EpochNotFinalized();
        if (claimed[epochId][msg.sender]) revert AlreadyClaimed();
        if (epoch.snapshotWeight == 0) revert NoWeight(); // Prevent division by zero

        // Use VESTED weight - critical for flash loan protection
        uint256 userWeight = vault.getVestedWeight(msg.sender);
        if (userWeight == 0) revert NoWeight();

        // Calculate proportional share based on vested weight
        uint256 userShare = (epoch.totalEmission * userWeight) / epoch.snapshotWeight;

        claimed[epochId][msg.sender] = true;

        // Mint DMD to user
        dmdToken.mint(msg.sender, userShare);

        emit Claimed(msg.sender, epochId, userShare);
    }

    /**
     * @notice Batch claim multiple epochs
     * @dev Uses VESTED weight for flash loan protection
     */
    function claimMultiple(uint256[] calldata epochIds) external {
        for (uint256 i = 0; i < epochIds.length; i++) {
            uint256 epochId = epochIds[i];

            EpochData memory epoch = epochs[epochId];
            if (!epoch.finalized) continue;
            if (claimed[epochId][msg.sender]) continue;
            if (epoch.snapshotWeight == 0) continue; // Prevent division by zero

            // Use VESTED weight - critical for flash loan protection
            uint256 userWeight = vault.getVestedWeight(msg.sender);
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
        if (distributionStartTime == 0) return 0;
        return (block.timestamp - distributionStartTime) / EPOCH_DURATION;
    }

    /**
     * @notice Calculate claimable amount for user in specific epoch
     * @dev Uses VESTED weight for accurate calculation
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

        // Use VESTED weight - critical for flash loan protection
        uint256 userWeight = vault.getVestedWeight(user);
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
     * @dev Uses VESTED weight for accurate calculation
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

            // Use VESTED weight - critical for flash loan protection
            uint256 userWeight = vault.getVestedWeight(user);
            if (userWeight == 0) continue;

            total += (epoch.totalEmission * userWeight) / epoch.snapshotWeight;
        }
    }
}
