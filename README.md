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
- To unlock tBTC, **100% of all DMD minted from that lock position must be burned**
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

- **Single Asset Only**: tBTC on Base
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

All non-emission allocations (Foundation, Founders, Developers, Contributors) follow the **Diamond Vesting Curve** (5% TGE + 95% linear over 7 years).

---

## Architecture

### Core Contracts

- **BTCReserveVault.sol** — tBTC locking, positions, weight tracking (checks PDC)
- **EmissionScheduler.sol** — Fixed annual emissions with 25% decay
- **MintDistributor.sol** — 7-day epoch-based distribution
- **RedemptionEngine.sol** — Enforces full burn-to-redeem
- **DMDToken.sol** — ERC-20 with capped supply and public burn
- **VestingContract.sol** — Long-term team & contributor vesting
- **ProtocolDefenseConsensus.sol** — Adapter-only (PDC)

### Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|

| BTCReserveVault | `0x02A2cC006FB2F0b4B59Dd30EA6613eE2BA84942E` |
| EmissionScheduler | `0x23F2f1dfE875ec1192d0b003185340509693eBcB` |
| MintDistributor | `0x08EBc0cE45eC551f0Ad3584538A0DF287F169b5c` |
| DMDToken | `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f` |
| RedemptionEngine | `0x70538c1067199834807d00BBCBE81246b305eB51` |
| VestingContract | `0xE09885C0ba03cdB1DADA52F1D7b41772c3144c32` |
| ProtocolDefenseConsensus (PDC) | `0x2c56CA0f4FcBbdBdF634bB6d77dCAD314e15b349` |
| tBTC (External) | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |

---

## Protocol Defense Consensus (PDC)

PDC is a **minimal voting system** that exists **ONLY** to manage external tBTC adapter integrations. It has **zero authority** over the monetary core.

### PDC CAN:
- Pause a compromised adapter
- Resume a paused adapter
- Approve new adapters
- Deprecate obsolete adapters

### PDC CANNOT:
- Change emission rates or caps
- Modify token supply or mint/burn
- Move, freeze, or seize any BTC
- Upgrade any contracts
- Change redemption rules

### Activation Conditions

PDC is **completely inert** until ALL conditions are met:

| Condition | Threshold |
|-----------|-----------|
| Time Since Deployment | ≥ 3 years |
| Circulating Supply | ≥ 30% of MAX_SUPPLY |
| Unique Holders | ≥ 10,000 addresses |

### Voting Parameters

| Parameter | Value |
|-----------|-------|
| Quorum | 60% of circulating supply |
| Approval | 75% of votes cast |
| Voting Period | 14 days |
| Execution Delay | 7 days |
| Cooldown | 30 days |

Voting: 1 DMD = 1 vote, no delegation, votes locked during voting period.

### Initial Adapter

tBTC is pre-approved as an initial adapter at deployment. The BTCReserveVault checks PDC to verify the adapter (tBTC) is active before accepting locks. If tBTC is ever compromised, PDC (after activation) can pause or deprecate it.

---

## Redemption Rule (Critical)

To unlock tBTC from a given position:

> **The user is required to burn 100% of the DMD minted from that lock position.**

Properties:
- No partial burns
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

## DMD Foundation

The DMD Foundation is a formal early community supporting the initial development and understanding of the DMD Protocol.

The Foundation does not control or govern the protocol. All monetary rules — including supply, emissions, and distribution — are immutable and enforced by smart contracts.

The protocol currently relies on tBTC, an external and independent system, as its default BTC adapter. As long as tBTC operates reliably, it is expected to remain the sole BTC integration used for emissions.

Any work by the Foundation related to alternative BTC connectivity is strictly preparatory and defensive in nature, intended only as a contingency to reduce long-term external dependency risk. Such alternatives are not active by default, do not affect protocol economics, and may never be used.

The Foundation does not manage markets, influence price, or provide investment advice. Its role is temporary by design and is expected to diminish as the public community becomes capable of sustaining the protocol independently.

---

## Intellectual Property Notice

The **Extreme Deflationary Digital Asset Mechanism (EDAD)** implemented by DMD Protocol is subject to a pending U.S. patent application.

Open-source code remains freely usable; the underlying economic mechanism is protected against unauthorized commercial replication.

---

**DMD Protocol v1.8.8**  \
Immutable • Bitcoin-backed • Structurally Deflationary

