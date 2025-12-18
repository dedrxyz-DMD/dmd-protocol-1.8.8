// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";

/**
 * @title RedemptionEngine
 * @notice Burns DMD to unlock tBTC from reserve vault
 * @dev Fully decentralized - no owner, no admin, no governance
 * @dev Enforces burn-to-redeem mechanism, position-based unlocking
 */
contract RedemptionEngine {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientDMD();
    error PositionLocked();
    error PositionNotFound();
    error AlreadyRedeemed();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;

    // Track redemptions: user => positionId => redeemed
    mapping(address => mapping(uint256 => bool)) public redeemed;

    // Track total burned per user for accounting
    mapping(address => uint256) public totalBurnedByUser;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Redeemed(
        address indexed user,
        uint256 indexed positionId,
        uint256 tbtcAmount,
        uint256 dmdBurned
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0)) {
            revert InvalidAmount();
        }
        dmdToken = _dmdToken;
        vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                          REDEMPTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Burn DMD to unlock tBTC from specific position
     * @param positionId Position identifier in vault
     * @param dmdAmount Amount of DMD to burn (must cover position weight)
     * @dev User must have unlocked position and sufficient DMD balance
     */
    function redeem(uint256 positionId, uint256 dmdAmount) external {
        if (dmdAmount == 0) revert InvalidAmount();
        if (redeemed[msg.sender][positionId]) revert AlreadyRedeemed();

        // Get position details from vault
        (
            uint256 tbtcAmount,
            ,  // lockMonths (skip)
            ,  // unlockTime (skip)
            uint256 weight
        ) = vault.getPosition(msg.sender, positionId);

        if (tbtcAmount == 0) revert PositionNotFound();
        if (!vault.isUnlocked(msg.sender, positionId)) revert PositionLocked();

        // Require burn amount >= position weight
        if (dmdAmount < weight) revert InsufficientDMD();

        // Mark as redeemed before external calls
        redeemed[msg.sender][positionId] = true;
        totalBurnedByUser[msg.sender] += dmdAmount;

        // Burn DMD from user
        dmdToken.transferFrom(msg.sender, address(this), dmdAmount);
        dmdToken.burn(dmdAmount);

        // Unlock tBTC from vault
        vault.redeem(msg.sender, positionId);

        emit Redeemed(msg.sender, positionId, tbtcAmount, dmdAmount);
    }

    /**
     * @notice Batch redeem multiple positions
     * @param positionIds Array of position identifiers
     * @param dmdAmounts Array of DMD amounts to burn per position
     */
    function redeemMultiple(
        uint256[] calldata positionIds,
        uint256[] calldata dmdAmounts
    ) external {
        if (positionIds.length != dmdAmounts.length) revert InvalidAmount();

        uint256 totalBurn = 0;

        // First pass: validate and accumulate
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 positionId = positionIds[i];
            uint256 dmdAmount = dmdAmounts[i];

            if (dmdAmount == 0) continue;
            if (redeemed[msg.sender][positionId]) continue;

            (
                uint256 tbtcAmount,
                ,  // lockMonths (skip)
                ,  // unlockTime (skip)
                uint256 weight
            ) = vault.getPosition(msg.sender, positionId);

            if (tbtcAmount == 0) continue;
            if (!vault.isUnlocked(msg.sender, positionId)) continue;
            if (dmdAmount < weight) continue;

            redeemed[msg.sender][positionId] = true;
            totalBurn += dmdAmount;
        }

        // Transfer and burn DMD first (atomic)
        if (totalBurn > 0) {
            totalBurnedByUser[msg.sender] += totalBurn;
            dmdToken.transferFrom(msg.sender, address(this), totalBurn);
            dmdToken.burn(totalBurn);
        }

        // Second pass: redeem from vault
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 positionId = positionIds[i];

            // Only process if we marked it as redeemed in first pass
            if (!redeemed[msg.sender][positionId]) continue;

            (uint256 tbtcAmount,,,) = vault.getPosition(msg.sender, positionId);

            // Skip if already processed by vault (amount would be 0)
            if (tbtcAmount == 0) continue;

            vault.redeem(msg.sender, positionId);

            emit Redeemed(msg.sender, positionId, tbtcAmount, dmdAmounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if position has been redeemed
     */
    function isRedeemed(address user, uint256 positionId) external view returns (bool) {
        return redeemed[user][positionId];
    }

    /**
     * @notice Calculate required DMD burn for position redemption
     * @dev Returns position weight (minimum burn amount)
     */
    function getRequiredBurn(address user, uint256 positionId)
        external
        view
        returns (uint256)
    {
        (
            uint256 tbtcAmount,
            ,  // lockMonths (skip)
            ,  // unlockTime (skip)
            uint256 weight
        ) = vault.getPosition(user, positionId);

        if (tbtcAmount == 0) return 0;
        return weight;
    }

    /**
     * @notice Check if position is redeemable
     * @dev Checks: not already redeemed, position exists, lock expired, user has DMD
     */
    function isRedeemable(address user, uint256 positionId)
        external
        view
        returns (bool)
    {
        if (redeemed[user][positionId]) return false;

        (
            uint256 tbtcAmount,
            ,  // lockMonths (skip)
            ,  // unlockTime (skip)
            uint256 weight
        ) = vault.getPosition(user, positionId);

        if (tbtcAmount == 0) return false;
        if (!vault.isUnlocked(user, positionId)) return false;
        if (dmdToken.balanceOf(user) < weight) return false;

        return true;
    }

    /**
     * @notice Get redemption status for user
     */
    function getUserRedemptionStats(address user)
        external
        view
        returns (
            uint256 totalBurned,
            uint256 currentDMDBalance
        )
    {
        return (
            totalBurnedByUser[user],
            dmdToken.balanceOf(user)
        );
    }
}
