// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";
import "./interfaces/IMintDistributor.sol";

/// @title RedemptionEngine - Burns DMD to unlock tBTC from vault
/// @dev User must burn ALL DMD minted from position to redeem tBTC
contract RedemptionEngine {
    error InsufficientDMD();
    error PositionLocked();
    error PositionNotFound();
    error AlreadyRedeemed();
    error InvalidAmount();
    error NoDMDMinted();

    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;
    IMintDistributor public immutable mintDistributor;

    mapping(address => mapping(uint256 => bool)) public redeemed;
    mapping(address => uint256) public totalBurnedByUser;

    event Redeemed(address indexed user, uint256 indexed positionId, uint256 tbtcAmount, uint256 dmdBurned);

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault, IMintDistributor _mintDistributor) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0) || address(_mintDistributor) == address(0)) revert InvalidAmount();
        dmdToken = _dmdToken;
        vault = _vault;
        mintDistributor = _mintDistributor;
    }

    /// @notice Redeem tBTC by burning ALL DMD minted from position
    /// @param positionId Position ID to redeem
    function redeem(uint256 positionId) external {
        if (redeemed[msg.sender][positionId]) revert AlreadyRedeemed();

        (uint256 tbtcAmount,,,) = vault.getPosition(msg.sender, positionId);
        if (tbtcAmount == 0) revert PositionNotFound();
        if (!vault.isUnlocked(msg.sender, positionId)) revert PositionLocked();

        uint256 requiredBurn = mintDistributor.getPositionDMDMinted(msg.sender, positionId);
        if (requiredBurn == 0) revert NoDMDMinted();

        redeemed[msg.sender][positionId] = true;
        totalBurnedByUser[msg.sender] += requiredBurn;

        dmdToken.transferFrom(msg.sender, address(this), requiredBurn);
        dmdToken.burn(requiredBurn);
        vault.redeem(msg.sender, positionId);

        emit Redeemed(msg.sender, positionId, tbtcAmount, requiredBurn);
    }

    /// @notice Redeem multiple positions by burning ALL DMD minted from each
    /// @param positionIds Array of position IDs to redeem
    function redeemMultiple(uint256[] calldata positionIds) external {
        uint256 len = positionIds.length;
        uint256 totalBurn = 0;
        uint256[] memory burns = new uint256[](len);

        // Calculate total burn and mark as redeemed
        for (uint256 i = 0; i < len;) {
            uint256 posId = positionIds[i];
            if (redeemed[msg.sender][posId]) {
                unchecked { ++i; }
                continue;
            }

            (uint256 tbtcAmount,,,) = vault.getPosition(msg.sender, posId);
            if (tbtcAmount == 0 || !vault.isUnlocked(msg.sender, posId)) {
                unchecked { ++i; }
                continue;
            }

            uint256 requiredBurn = mintDistributor.getPositionDMDMinted(msg.sender, posId);
            if (requiredBurn == 0) {
                unchecked { ++i; }
                continue;
            }

            redeemed[msg.sender][posId] = true;
            burns[i] = requiredBurn;
            totalBurn += requiredBurn;
            unchecked { ++i; }
        }

        // Burn all DMD at once
        if (totalBurn > 0) {
            totalBurnedByUser[msg.sender] += totalBurn;
            dmdToken.transferFrom(msg.sender, address(this), totalBurn);
            dmdToken.burn(totalBurn);
        }

        // Redeem positions and emit events
        for (uint256 i = 0; i < len;) {
            if (burns[i] == 0) {
                unchecked { ++i; }
                continue;
            }

            (uint256 tbtcAmount,,,) = vault.getPosition(msg.sender, positionIds[i]);
            vault.redeem(msg.sender, positionIds[i]);
            emit Redeemed(msg.sender, positionIds[i], tbtcAmount, burns[i]);
            unchecked { ++i; }
        }
    }

    /// @notice Check if position has been redeemed
    function isRedeemed(address user, uint256 positionId) external view returns (bool) {
        return redeemed[user][positionId];
    }

    /// @notice Get required DMD burn amount (all DMD minted to position)
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return Required DMD to burn
    function getRequiredBurn(address user, uint256 positionId) external view returns (uint256) {
        (uint256 tbtcAmount,,,) = vault.getPosition(user, positionId);
        if (tbtcAmount == 0) return 0;
        return mintDistributor.getPositionDMDMinted(user, positionId);
    }

    /// @notice Check if position is redeemable
    /// @param user Position owner
    /// @param positionId Position ID
    /// @return True if position can be redeemed
    function isRedeemable(address user, uint256 positionId) external view returns (bool) {
        if (redeemed[user][positionId]) return false;
        (uint256 tbtcAmount,,,) = vault.getPosition(user, positionId);
        if (tbtcAmount == 0 || !vault.isUnlocked(user, positionId)) return false;

        uint256 requiredBurn = mintDistributor.getPositionDMDMinted(user, positionId);
        return requiredBurn > 0 && dmdToken.balanceOf(user) >= requiredBurn;
    }
}
