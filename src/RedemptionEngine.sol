// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/IDMDToken.sol";
import "./interfaces/IBTCReserveVault.sol";

/// @title RedemptionEngine - Burns DMD to unlock tBTC from vault
/// @dev Fully decentralized, burn-to-redeem mechanism
contract RedemptionEngine {
    error InsufficientDMD();
    error PositionLocked();
    error PositionNotFound();
    error AlreadyRedeemed();
    error InvalidAmount();

    IDMDToken public immutable dmdToken;
    IBTCReserveVault public immutable vault;

    mapping(address => mapping(uint256 => bool)) public redeemed;
    mapping(address => uint256) public totalBurnedByUser;

    event Redeemed(address indexed user, uint256 indexed positionId, uint256 tbtcAmount, uint256 dmdBurned);

    constructor(IDMDToken _dmdToken, IBTCReserveVault _vault) {
        if (address(_dmdToken) == address(0) || address(_vault) == address(0)) revert InvalidAmount();
        dmdToken = _dmdToken;
        vault = _vault;
    }

    function redeem(uint256 positionId, uint256 dmdAmount) external {
        if (dmdAmount == 0) revert InvalidAmount();
        if (redeemed[msg.sender][positionId]) revert AlreadyRedeemed();

        (uint256 tbtcAmount,,, uint256 weight) = vault.getPosition(msg.sender, positionId);
        if (tbtcAmount == 0) revert PositionNotFound();
        if (!vault.isUnlocked(msg.sender, positionId)) revert PositionLocked();
        if (dmdAmount < weight) revert InsufficientDMD();

        redeemed[msg.sender][positionId] = true;
        totalBurnedByUser[msg.sender] += dmdAmount;

        dmdToken.transferFrom(msg.sender, address(this), dmdAmount);
        dmdToken.burn(dmdAmount);
        vault.redeem(msg.sender, positionId);

        emit Redeemed(msg.sender, positionId, tbtcAmount, dmdAmount);
    }

    function redeemMultiple(uint256[] calldata positionIds, uint256[] calldata dmdAmounts) external {
        if (positionIds.length != dmdAmounts.length) revert InvalidAmount();

        uint256 totalBurn = 0;

        for (uint256 i = 0; i < positionIds.length; i++) {
            if (dmdAmounts[i] == 0 || redeemed[msg.sender][positionIds[i]]) continue;

            (uint256 tbtcAmount,,, uint256 weight) = vault.getPosition(msg.sender, positionIds[i]);
            if (tbtcAmount == 0 || !vault.isUnlocked(msg.sender, positionIds[i]) || dmdAmounts[i] < weight) continue;

            redeemed[msg.sender][positionIds[i]] = true;
            totalBurn += dmdAmounts[i];
        }

        if (totalBurn > 0) {
            totalBurnedByUser[msg.sender] += totalBurn;
            dmdToken.transferFrom(msg.sender, address(this), totalBurn);
            dmdToken.burn(totalBurn);
        }

        for (uint256 i = 0; i < positionIds.length; i++) {
            if (!redeemed[msg.sender][positionIds[i]]) continue;

            (uint256 tbtcAmount,,,) = vault.getPosition(msg.sender, positionIds[i]);
            if (tbtcAmount == 0) continue;

            vault.redeem(msg.sender, positionIds[i]);
            emit Redeemed(msg.sender, positionIds[i], tbtcAmount, dmdAmounts[i]);
        }
    }

    function isRedeemed(address user, uint256 positionId) external view returns (bool) { return redeemed[user][positionId]; }

    function getRequiredBurn(address user, uint256 positionId) external view returns (uint256) {
        (uint256 tbtcAmount,,, uint256 weight) = vault.getPosition(user, positionId);
        return tbtcAmount == 0 ? 0 : weight;
    }

    function isRedeemable(address user, uint256 positionId) external view returns (bool) {
        if (redeemed[user][positionId]) return false;
        (uint256 tbtcAmount,,, uint256 weight) = vault.getPosition(user, positionId);
        return tbtcAmount > 0 && vault.isUnlocked(user, positionId) && dmdToken.balanceOf(user) >= weight;
    }
}
