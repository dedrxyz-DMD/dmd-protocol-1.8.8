# 📘 DMD PROTOCOL WHITEPAPER
## Version 1.8.8
**Powered by the Extreme Deflationary Digital Asset Mechanism (EDAD)**

**Network**: Base Mainnet  
**Reserve Asset**: tBTC (Threshold Network Bitcoin)  
**Status**: Production Ready  
**Date**: December 2025  

---

## EXECUTIVE SUMMARY

DMD Protocol is a decentralized, immutable Bitcoin liquidity and emission protocol deployed on Base. It implements the **Extreme Deflationary Digital Asset Mechanism (EDAD)** — a reserve-locked, emission-capped, mandatory burn-to-redeem economic system.

Users lock **tBTC** to earn **DMD** from a fixed, declining emission schedule. To unlock their tBTC, users must **irreversibly burn 100% of all DMD minted from that specific locked position**, permanently reducing total circulating supply.

This creates a closed, one-way economic loop where **minting is conditional, burning is mandatory, and deflation is market-driven**.

The protocol has:
- No governance
- No admin keys
- No upgrades
- No emergency controls

Once deployed, DMD Protocol runs autonomously and permanently.

---

## TABLE OF CONTENTS

1. Introduction
2. Design Principles
3. The EDAD Mechanism
4. Protocol Architecture
5. Tokenomics
6. Emission Model
7. Redemption & Deflation
8. Protocol Defense Consensus (PDC)
8A. DMD Foundation — Purpose and Role
9. Security Model
10. Technical Specification
11. Audits & Testing
12. Risks & Disclosures
13. Roadmap
14. Conclusion
15. Intellectual Property Notice  

---

## 1. INTRODUCTION

### 1.1 Background

Bitcoin is the most secure and scarce digital asset, yet remains largely idle in decentralized finance. Existing BTC-based protocols rely on custodians, inflationary incentives, governance-controlled emissions, or reversible supply mechanics.

DMD Protocol introduces a structurally different model: **Bitcoin-backed scarcity enforced by code**, not discretion.

### 1.2 Objectives

DMD Protocol is designed to be:
- Structurally deflationary
- Governance-free
- Whale-resistant
- Fully immutable
- Market-reactive
- Audit-verifiable

---

## 2. DESIGN PRINCIPLES

### 2.1 Single-Asset Simplicity

DMD Protocol accepts **only tBTC**:
- No WBTC
- No synthetic derivatives
- No multi-asset risk

tBTC provides decentralized custody, threshold security, and Ethereum-native settlement on Base.

### 2.2 Time-Weighted Commitment

Users lock tBTC for fixed durations. Longer commitments receive higher weight multipliers, increasing emission share.

Weight **vests over time**, preventing flash-loan or short-term manipulation.

---

## 3. THE EDAD MECHANISM

### 3.1 Definition

The **Extreme Deflationary Digital Asset Mechanism (EDAD)** is defined by five immutable properties:

1. **Reserve-Locked Minting**  
   DMD is minted exclusively through tBTC locking.

2. **Fixed, Declining Emission Pool**  
   Emissions follow a deterministic decay schedule, independent of participation.

3. **Mandatory Burn-to- Redeem**  
   Redemption of tBTC requires irreversible destruction of DMD.

4. **Market-Behavior-Driven Deflation**  
   User redemption behavior directly determines deflation rate.

5. **Permanent Supply Reduction**  
   Burned DMD is removed forever; supply may fall below all caps.

### 3.2 Closed Economic Loop

```
Lock tBTC → Mint DMD → Burn DMD → Unlock tBTC
```

This loop is irreversible and cannot be bypassed.

---

## 4. PROTOCOL ARCHITECTURE

### 4.1 Core Smart Contracts

- **ProtocolDefenseConsensus (PDC)**
  Adapter-only governance for managing external BTC bridges. Pre-approves tBTC at deployment.

- **BTCReserveVault**
  Handles tBTC locking, position tracking, and emission accounting. Checks PDC for adapter status.

- **EmissionScheduler**
  Controls fixed, decaying annual emissions.

- **MintDistributor**
  Distributes weekly emissions proportionally by vested weight.

- **RedemptionEngine**
  Enforces full burn-to-redeem logic.

- **DMDToken (ERC-20)**
  Fixed-supply token with public burn functionality. Tracks unique holder count for PDC activation.

- **VestingContract**
  Diamond Vesting Curve for non-emission allocations.

### 4.2 Immutability Guarantees

- No proxy contracts
- No upgrade paths
- No owner privileges post-deployment
- All critical parameters hardcoded

---

## 5. TOKENOMICS

### 5.1 Supply Overview

| Category | Amount |
|--------|--------|
| Maximum Possible Supply | 18,000,000 DMD |
| Emission-Reachable Supply | 14,400,000 DMD |
| Real Circulating Supply | Variable, deflationary |

Real circulating supply is **always ≤ 14.4M** and may decrease indefinitely.

### 5.2 Distribution Allocation

| Allocation | % | Amount | Vesting |
|-----------|---|--------|--------|
| BTC Mining Emissions | 80% | 14,400,000 | EDAD emissions |
| Foundation | 10% | 1,800,000 | Diamond Vesting Curve |
| Founders | 5% | 900,000 | Diamond Vesting Curve |
| Developers | 2.5% | 450,000 | Diamond Vesting Curve |
| Contributors | 2.5% | 450,000 | Diamond Vesting Curve |
| **Total** | **100%** | **18,000,000** | |

---

## 6. EMISSION MODEL

### 6.1 Annual Quartering Schedule

Emissions decay by **25% annually**:

| Year | Emission |
|----|----------|
| 1 | 3,600,000 |
| 2 | 2,700,000 |
| 3 | 2,025,000 |
| 4 | 1,518,750 |
| 5 | 1,139,062 |
| 6 | 854,296 |
| … | ×0.75 annually |

Emissions permanently stop when **14.4M DMD** is minted.

### 6.2 Epoch Distribution

- 7-day epochs
- Permissionless finalization
- Proportional to **vested lock weight**
- Oracle-free

---

## 7. REDEMPTION & DEFLATION

### 7.1 Mandatory Full Burn Rule

To unlock tBTC from a given position:

> **The user must burn 100% of all DMD minted from that specific locked position.**

Properties:
- No partial redemption
- No substitution with externally acquired DMD

### 7.2 Early Unlock Option

Users may request early unlock before the lock period expires:

- **Request**: Call `requestEarlyUnlock(positionId)`
- **Waiting Period**: 30 days from request
- **Weight Removal**: Immediate (stops earning DMD rewards)
- **Cancellation**: Can cancel anytime before redemption to restore weight
- **Redemption**: After 30 days, burn all earned DMD to unlock tBTC

This provides user flexibility while maintaining protocol security.

### 7.3 Market-Driven Deflation

- Market stress → more redemptions → accelerated burns
- Market optimism → fewer redemptions → supply freeze

Human behavior becomes the **scarcity engine**.

---

## 8. PROTOCOL DEFENSE CONSENSUS (PDC)

### 8.1 Purpose & Scope

The Protocol Defense Consensus (PDC) is a **minimal, adapter-only system** that exists solely to manage external tBTC adapter integrations. PDC has **zero authority** over the monetary core.

**PDC CAN:**
- Pause a compromised adapter
- Resume a paused adapter
- Approve new adapters
- Deprecate obsolete adapters

**PDC CANNOT:**
- Change emission rates or caps
- Modify token supply or max supply
- Mint or burn DMD tokens
- Move, freeze, or seize any BTC
- Freeze user balances
- Upgrade any core contracts
- Change redemption rules
- Modify vesting schedules

### 8.2 Activation Conditions

PDC is **completely inert** until ALL three conditions are met:

| Condition | Threshold | Rationale |
|-----------|-----------|-----------|
| Time Since Deployment | ≥ 3 years | Protocol stability proven |
| Circulating Supply | ≥ 30% of MAX_SUPPLY | Sufficient distribution |
| Unique Holders | ≥ 10,000 addresses | Decentralized ownership |

Activation is:
- **Deterministic**: No admin can trigger early
- **Irreversible**: Once active, cannot deactivate
- **Automatic**: Checked on every proposal attempt

### 8.3 Allowed Actions

PDC is limited to exactly four adapter management actions:

| Action | Effect | Use Case |
|--------|--------|----------|
| PAUSE_ADAPTER | Halt adapter deposits/emissions | Emergency response to exploit |
| RESUME_ADAPTER | Restore paused adapter | After security fix verified |
| APPROVE_ADAPTER | Whitelist new adapter | Expand to new BTC bridges |
| DEPRECATE_ADAPTER | Permanently disable adapter | Sunset obsolete bridges |

### 8.4 Voting Mechanics

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Quorum | 60% of circulating supply | Very high participation required |
| Approval | 75% of votes cast | Supermajority consensus |
| Voting Period | 14 days | Adequate deliberation time |
| Execution Delay | 7 days | Time for user response |
| Cooldown | 30 days | Prevent governance spam |

**Voting Rules:**
- 1 DMD = 1 vote (no quadratic, no delegation)
- Votes locked during voting period
- No vote changes after casting
- Only one proposal active at a time

### 8.5 State Machine

```
IDLE → VOTING (14 days) → QUEUED (7 days) → EXECUTED → COOLDOWN (30 days) → IDLE
         ↓ (fails quorum/approval)
       IDLE
```

- **IDLE**: No active proposal, system ready
- **VOTING**: 14-day voting window open
- **QUEUED**: Approved, awaiting execution delay
- **EXECUTED**: Action completed
- **COOLDOWN**: 30-day pause before next proposal

### 8.6 Security Guarantees

1. **Monetary Immutability**: PDC has no access to EmissionScheduler, DMDToken mint/burn, or RedemptionEngine
2. **No Upgrade Path**: PDC contract itself is immutable
3. **Delayed Execution**: 7-day delay allows users to exit if they disagree
4. **High Thresholds**: 60% quorum + 75% approval prevents minority capture
5. **Rate Limiting**: 30-day cooldown prevents governance attacks

---

## 8A. DMD FOUNDATION — PURPOSE AND ROLE

The DMD Foundation is a formal early community formed to support initial technical coordination and public understanding of the DMD Protocol.

The Foundation does not control, administer, or govern the DMD Protocol. All monetary rules of the protocol — including maximum supply, emission schedules, distribution logic, and issuance conditions — are permanently fixed and enforced exclusively by immutable smart contracts. These rules cannot be modified by the Foundation, its participants, or any external party.

The Foundation has no discretionary authority over protocol behavior and cannot influence token issuance, economic outcomes, or market activity.

The DMD Protocol currently relies on tBTC, an external and independent system, as its default BTC adapter. As long as tBTC continues to operate reliably, the protocol is expected to continue using tBTC exclusively for BTC-related functionality, including emissions.

The Foundation's role is strictly limited to:

- Supporting open discussion, documentation, and education to help form a genuine, informed public community
- Encouraging accurate, non-misleading understanding of the protocol to reduce confusion, misinformation, or misrepresentation
- Conducting research and preparatory technical work related to alternative BTC connectivity solely as a contingency, intended to reduce long-term external dependency risk

Any alternative BTC integration researched or developed by the Foundation is not active by default, does not affect the protocol's monetary rules, and may never be used. Activation of any alternative mechanism, if ever required, would occur strictly through the protocol's predefined on-chain processes, including the Protocol Defense Consensus (PDC) when and if it becomes active.

The Foundation does not manage markets, influence price, guarantee value, or provide investment advice. Participation in the protocol is voluntary and undertaken at each user's own responsibility.

The Foundation is temporary by design. As the public community becomes sufficiently decentralized, knowledgeable, and capable of sustaining the ecosystem independently, the Foundation is expected to progressively reduce its involvement and may ultimately dissolve, leaving the DMD Protocol supported entirely by open, public participation.

---

## 9. SECURITY MODEL

### 9.1 Economic Security

- Fixed emissions prevent inflation exploits
- Full burn requirement prevents exit arbitrage
- No governance removes manipulation vectors
- Whale deposits do not increase total supply

### 9.2 Technical Security

- Solidity 0.8.x overflow protection
- CEI pattern enforced
- 10-day weight vesting
- Position limits prevent gas DoS
- No oracle dependencies in core logic

---

## 10. TECHNICAL SPECIFICATION

- **Chain**: Base (Chain ID 8453)
- **Reserve Asset**: tBTC
  `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`
- **Epoch Length**: 7 days
- **Max Weight Multiplier**: 1.48× (24 months)
- **Weight Vesting**: 10 days (7-day warmup + 3-day linear)
- **Early Unlock Delay**: 30 days

### Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| ProtocolDefenseConsensus (PDC) | `0x2c56CA0f4FcBbdBdF634bB6d77dCAD314e15b349` |
| BTCReserveVault | `0x02A2cC006FB2F0b4B59Dd30EA6613eE2BA84942E` |
| EmissionScheduler | `0x23F2f1dfE875ec1192d0b003185340509693eBcB` |
| MintDistributor | `0x08EBc0cE45eC551f0Ad3584538A0DF287F169b5c` |
| DMDToken | `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f` |
| RedemptionEngine | `0x70538c1067199834807d00BBCBE81246b305eB51` |
| VestingContract | `0xE09885C0ba03cdB1DADA52F1D7b41772c3144c32` |
| tBTC (External) | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |

---

## 11. AUDITS & TESTING

- 160+ automated tests
- 100% critical-path coverage
- Flash-loan attack simulations passed
- Supply invariants verified
- Full burn redemption logic tested

Security rating: **A+**

---

## 12. RISKS & DISCLOSURES

- Immutability means no fixes post-deployment
- Early unlock requires 30-day waiting period (weight removed immediately)
- DMD liquidity depends on adoption
- Users must self-custody private keys
- Protocol provided "as is"

This document is not financial advice.

---

## 13. ROADMAP

- ✅ Architecture finalized
- ✅ EDAD patent filed
- ✅ Testnet complete
- 🎯 Base mainnet deployment
- 🎯 Epoch 0 emissions
- 🎯 Analytics dashboards
- 🎯 Ecosystem integrations

No protocol upgrades planned.

---

## 14. CONCLUSION

DMD Protocol introduces a new monetary primitive:

- Bitcoin-backed
- Structurally deflationary
- Fully immutable
- Market-reactive
- Governance-free

EDAD converts human behavior into an on-chain deflation engine.

This is not yield farming.  
This is **programmable scarcity**.

---

## 15. INTELLECTUAL PROPERTY NOTICE

The **Extreme Deflationary Digital Asset Mechanism (EDAD)** implemented by DMD Protocol is the subject of a pending U.S. patent application.

Open-source code remains freely usable; the economic mechanism is protected from unauthorized commercial replication.

---

**END OF WHITEPAPER**  
**DMD Protocol v1.8.8**  
**Base Mainnet**  
**December 2025**
