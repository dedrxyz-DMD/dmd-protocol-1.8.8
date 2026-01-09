// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDMDToken} from "./interfaces/IDMDToken.sol";
import {IBTCReserveVault} from "./interfaces/IBTCReserveVault.sol";
import {IMintDistributor} from "./interfaces/IMintDistributor.sol";

/// @title RedemptionEngine - Burns DMD to unlock tBTC from vault
/// @dev User must burn ALL DMD minted from position to redeem tBTC
/// @dev If user never claimed DMD, they can redeem without burning
/// @dev v1.8.9 - Security fix: reentrancy protection added
contract RedemptionEngine {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientDMDBalance();
    error InsufficientDMDAllowance();
    error PositionLocked();
    error PositionNotFound();
    error AlreadyRedeemed();
    error ZeroAddressNotAllowed();
    error ReentrancyGuard();

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IDMDToken public immutable DMD_TOKEN;
    IBTCReserveVault public immutable VAULT;
    IMintDistributor public immutable MINT_DISTRIBUTOR;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    /// @notice Tracks redeemed positions: user => positionId => redeemed
    mapping(address => mapping(uint256 => bool)) public redeemed;

    /// @notice Total DMD burned by each user
    mapping(address => uint256) public totalBurnedByUser;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Redeemed(address indexed user, uint256 indexed positionId, uint256 tbtcAmount, uint256 dmdBurned);

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

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault, IMintDistributor _mintDistributor) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0) || address(_mintDistributor) == address(0)) revert ZeroAddressNotAllowed();
        DMD_TOKEN = _dmdToken;
        VAULT = _vault;
        MINT_DISTRIBUTOR = _mintDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Redeem tBTC by burning ALL DMD minted from position
    /// @dev If no DMD was minted (user never claimed), redemption is free
    /// @param positionId Position ID to redeem
    function redeem(uint256 positionId) external nonReentrant {
        if (redeemed[msg.sender][positionId]) revert AlreadyRedeemed();

        (uint256 tbtcAmount,,,) = VAULT.getPosition(msg.sender, positionId);
        if (tbtcAmount == 0) revert PositionNotFound();
        if (!VAULT.isUnlocked(msg.sender, positionId)) revert PositionLocked();

        uint256 requiredBurn = MINT_DISTRIBUTOR.getPositionDmdMinted(msg.sender, positionId);

        // Mark as redeemed BEFORE any external calls (CEI pattern)
        redeemed[msg.sender][positionId] = true;

        // Only burn if DMD was minted to this position
        if (requiredBurn > 0) {
            // Check user has enough balance
            if (DMD_TOKEN.balanceOf(msg.sender) < requiredBurn) revert InsufficientDMDBalance();
            // Check user has approved this contract
            if (DMD_TOKEN.allowance(msg.sender, address(this)) < requiredBurn) revert InsufficientDMDAllowance();

            totalBurnedByUser[msg.sender] += requiredBurn;

            // Transfer and burn DMD
            bool success = DMD_TOKEN.transferFrom(msg.sender, address(this), requiredBurn);
            if (!success) revert InsufficientDMDBalance();

            DMD_TOKEN.burn(requiredBurn);
        }

        // Redeem tBTC from vault
        VAULT.redeem(msg.sender, positionId);

        emit Redeemed(msg.sender, positionId, tbtcAmount, requiredBurn);
    }

    /// @notice Redeem multiple positions by burning ALL DMD minted from each
    /// @dev Positions with no DMD minted can still be redeemed (free redemption)
    /// @param positionIds Array of position IDs to redeem
    function redeemMultiple(uint256[] calldata positionIds) external nonReentrant {
        uint256 len = positionIds.length;
        uint256 totalBurn = 0;
        uint256[] memory burns = new uint256[](len);
        uint256[] memory tbtcAmounts = new uint256[](len);
        bool[] memory shouldRedeem = new bool[](len);

        // Phase 1: Validate and calculate total burn
        for (uint256 i = 0; i < len;) {
            uint256 posId = positionIds[i];

            if (redeemed[msg.sender][posId]) {
                unchecked { ++i; }
                continue;
            }

            (uint256 tbtcAmount,,,) = VAULT.getPosition(msg.sender, posId);
            if (tbtcAmount == 0 || !VAULT.isUnlocked(msg.sender, posId)) {
                unchecked { ++i; }
                continue;
            }

            uint256 requiredBurn = MINT_DISTRIBUTOR.getPositionDmdMinted(msg.sender, posId);

            // Mark as redeemed BEFORE external calls (CEI pattern)
            redeemed[msg.sender][posId] = true;
            shouldRedeem[i] = true;
            burns[i] = requiredBurn;
            tbtcAmounts[i] = tbtcAmount;
            totalBurn += requiredBurn;

            unchecked { ++i; }
        }

        // Phase 2: Check DMD balance and allowance, then burn all at once
        if (totalBurn > 0) {
            if (DMD_TOKEN.balanceOf(msg.sender) < totalBurn) revert InsufficientDMDBalance();
            if (DMD_TOKEN.allowance(msg.sender, address(this)) < totalBurn) revert InsufficientDMDAllowance();

            totalBurnedByUser[msg.sender] += totalBurn;

            bool success = DMD_TOKEN.transferFrom(msg.sender, address(this), totalBurn);
            if (!success) revert InsufficientDMDBalance();

            DMD_TOKEN.burn(totalBurn);
        }

        // Phase 3: Redeem tBTC from vault for each position
        for (uint256 i = 0; i < len;) {
            if (!shouldRedeem[i]) {
                unchecked { ++i; }
                continue;
            }

            VAULT.redeem(msg.sender, positionIds[i]);
            emit Redeemed(msg.sender, positionIds[i], tbtcAmounts[i], burns[i]);

            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if position has been redeemed
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return True if already redeemed
    function isRedeemed(address user, uint256 positionId) external view returns (bool) {
        return redeemed[user][positionId];
    }

    /// @notice Get required DMD burn amount (all DMD minted to position)
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return Required DMD to burn
    function getRequiredBurn(address user, uint256 positionId) external view returns (uint256) {
        (uint256 tbtcAmount,,,) = VAULT.getPosition(user, positionId);
        if (tbtcAmount == 0) return 0;
        return MINT_DISTRIBUTOR.getPositionDmdMinted(user, positionId);
    }

    /// @notice Check if position is redeemable
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return True if position can be redeemed
    function isRedeemable(address user, uint256 positionId) external view returns (bool) {
        if (redeemed[user][positionId]) return false;

        (uint256 tbtcAmount,,,) = VAULT.getPosition(user, positionId);
        if (tbtcAmount == 0 || !VAULT.isUnlocked(user, positionId)) return false;

        uint256 requiredBurn = MINT_DISTRIBUTOR.getPositionDmdMinted(user, positionId);
        // Can redeem if no DMD minted OR if user has enough DMD to burn
        return requiredBurn == 0 || DMD_TOKEN.balanceOf(user) >= requiredBurn;
    }

    /// @notice Get total DMD burned by a user
    /// @param user User address
    /// @return Total DMD burned
    function getTotalBurnedByUser(address user) external view returns (uint256) {
        return totalBurnedByUser[user];
    }
}
