# DMD Protocol v1.8.8 — EDAD / tBTC Only

> Immutable Bitcoin Liquidity & Emission Protocol on Base

**Status**: Production Ready  \
**Network**: Base Mainnet  \
**Reserve Asset**: tBTC (Threshold Network Bitcoin)  \
**Tests**: 160/160 passing (100%)

---

## Overview

DMD Protocol is a fully immutable, governance-free protocol that allows users to lock **tBTC** on Base to earn **DMD** emissions under the **Extreme Deflationary Digital Asset Mechanism (EDAD)**.

The protocol enforces a strict **mint → burn → unlock** economic loop:

- tBTC is locked to mint DMD
- DMD is emitted from a fixed, declining supply schedule
- To unlock tBTC, **100% of all DMD minted from that specific lock position must be burned**
- Burned DMD is destroyed permanently

There are **no upgrades, no admin keys, no governance, and no emergency controls**. Once deployed, the system operates autonomously forever.

---

## Core Properties (EDAD)

- **Reserve-Locked Minting**: DMD is minted only via tBTC locking
- **Fixed Emissions**: Annual emissions decay by 25%, independent of deposits
- **Mandatory Full Burn-to- Redeem**: No partial unlocks, no alternative exits
- **Market-Driven Deflation**: User redemption behavior determines supply collapse
- **Permanent Supply Reduction**: Burned DMD can never be reminted

---

## Key Features

- **Single Asset Only**: tBTC on Base (no WBTC, no multi-asset logic)
- **Strict Immutability**: No governance, no upgrades, no multisig
- **Flash Loan Resistance**: 10-day weight vesting period
- **Time-Weighted Participation**: Lock multipliers up to 1.48× (24 months)
- **Deflationary Tokenomics**: 18M max supply, 14.4M emission cap
- **Audit-Grade**: 160 comprehensive tests, all passing

---

## Tokenomics Summary

- **Maximum Supply**: 18,000,000 DMD (hard cap)
- **Emission-Reachable Supply**: 14,400,000 DMD
- **Real Circulating Supply**: Variable, permanently deflationary

### Distribution Allocation

| Allocation | % | Amount |
|-----------|---|--------|
| BTC Mining Emissions | 80% | 14,400,000 |
| Foundation | 10% | 1,800,000 |
| Founders | 5% | 900,000 |
| Developers | 2.5% | 450,000 |
| Contributors | 2.5% | 450,000 |
| **Total** | **100%** | **18,000,000** |

All non-emission allocations follow the **Diamond Vesting Curve** (5% TGE + 95% linear over 7 years).

---

## Architecture

### Core Contracts

- **BTCReserveVault.sol** — tBTC locking, positions, weight tracking
- **EmissionScheduler.sol** — Fixed annual emissions with 25% decay
- **MintDistributor.sol** — 7-day epoch-based distribution
- **RedemptionEngine.sol** — Enforces full burn-to-redeem
- **DMDToken.sol** — ERC-20 with capped supply and public burn
- **VestingContract.sol** — Long-term team & contributor vesting

**tBTC (Base Mainnet)**: `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`
**DMD token (Base Mainnet)**: `0xf93d0A59b6e77b092cb46D45387de318Cd6DBbdC`
---

## Redemption Rule (Critical)

To unlock tBTC from a given position:

> **The user must burn 100% of all DMD minted from that exact lock position.**

Properties:
- No partial burns
- No substitution with externally acquired DMD
- No governance exceptions

### Early Unlock Option

Users can request early unlock before lock period expires:

1. Call `requestEarlyUnlock(positionId)` — weight removed immediately
2. Wait 30 days
3. Call `redeem(positionId)` — burn all earned DMD, get tBTC back

Can cancel anytime with `cancelEarlyUnlock(positionId)` to restore weight.

---

## Security Model

### Flash Loan Protection

- Days 0–7: 0% weight (epoch delay)
- Days 7–10: Linear vesting (0% → 100%)
- Day 10+: Full weight active

### Additional Protections

- CEI pattern enforced throughout
- Solidity 0.8.x overflow safety
- MAX_POSITIONS_PER_USER = 100
- No oracles in core logic

---

## Testing & Verification

- **Total Tests**: 160+
- **Coverage**: 100% of critical paths
- Flash-loan attack simulations passed
- Supply invariants verified

Security posture: **A+**

---

## Version Information

- **Protocol Version**: 1.8.8
- **Solidity**: ^0.8.20
- **Network**: Base Mainnet
- **Upgradeability**: None

---

## Documentation

- 📘 Whitepaper: `DMD_Protocol_Whitepaper_v1.8.8.md`
- 📂 Contracts: `/src`
- 🧪 Tests: `/test`

---

## Intellectual Property Notice

The **Extreme Deflationary Digital Asset Mechanism (EDAD)** implemented by DMD Protocol is subject to a pending U.S. patent application.

Open-source code remains freely usable; the underlying economic mechanism is protected against unauthorized commercial replication.

---

**DMD Protocol v1.8.8**  \
Immutable • Bitcoin-backed • Structurally Deflationary

