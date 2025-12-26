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
8. Security Model  
9. Technical Specification  
10. Audits & Testing  
11. Risks & Disclosures  
12. Roadmap  
13. Conclusion  
14. Intellectual Property Notice  

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

3. **Mandatory Burn-to-Redeem**  
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

- **BTCReserveVault**  
  Handles tBTC locking, position tracking, and emission accounting.

- **EmissionScheduler**  
  Controls fixed, decaying annual emissions.

- **MintDistributor**  
  Distributes weekly emissions proportionally by vested weight.

- **RedemptionEngine**  
  Enforces full burn-to-redeem logic.

- **DMDToken (ERC-20)**  
  Fixed-supply token with public burn functionality.

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

All non-emission allocations follow the **Diamond Vesting Curve** (5% TGE + 95% linear over 7 years).

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

> **The user must burn the entire amount of DMD minted from that specific locked position.**

No partial redemption.

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

## 8. SECURITY MODEL

### 8.1 Economic Security

- Fixed emissions prevent inflation exploits
- Full burn requirement prevents exit arbitrage
- No governance removes manipulation vectors
- Whale deposits do not increase total supply

### 8.2 Technical Security

- Solidity 0.8.x overflow protection
- CEI pattern enforced
- 10-day weight vesting
- Position limits prevent gas DoS
- No oracle dependencies in core logic

---

## 9. TECHNICAL SPECIFICATION

### 9.1 Network & Parameters

- **Chain**: Base Mainnet (Chain ID 8453)
- **Epoch Length**: 7 days
- **Max Weight Multiplier**: 1.48× (24 months)
- **Weight Vesting**: 10 days (7-day warmup + 3-day linear)
- **Early Unlock Delay**: 30 days

### 9.2 Deployed Contracts

| Contract | Address |
|----------|---------|
| **DMD Token** | `0xf93d0A59b6e77b092cb46D45387de318Cd6DBbdC` |
| **BTC Reserve Vault** | `0x06e0cd192d613636562629c1fb3536bC7271c829` |
| **Emission Scheduler** | `0x68e0dc98221c432C41E2713937c113A3F8A345C5` |
| **Mint Distributor** | `0xD982570b4203AcB76FEEcA49DC2fc484d20a1F00` |
| **Redemption Engine** | `0xD4601b3c872bBd2DF761beAA4b96d4bE0A1565c4` |
| **Vesting Contract** | `0x0055D2058797dcF0f83bB29815DB5f8C175f4f46` |
| **tBTC (External)** | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |

All contracts are **verified on BaseScan** and fully immutable.

---

## 10. AUDITS & TESTING

- 160+ automated tests
- 100% critical-path coverage
- Flash-loan attack simulations passed
- Supply invariants verified
- Full burn redemption logic tested

Security rating: **A+**

---

## 11. ROADMAP

- ✅ Architecture finalized
- ✅ EDAD patent filed
- ✅ Testnet complete
- ✅ Base mainnet deployment
- 🎯 Epoch 0 emissions
- 🎯 Analytics dashboards
- 🎯 Ecosystem integrations

No protocol upgrades planned.

---

## 12. CONCLUSION

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

## 13. INTELLECTUAL PROPERTY NOTICE

The **Extreme Deflationary Digital Asset Mechanism (EDAD)** implemented by DMD Protocol is the subject of a pending U.S. patent application.

Open-source code remains freely usable; the economic mechanism is protected from unauthorized commercial replication.

---

**END OF WHITEPAPER**  
**DMD Protocol v1.8.8**  
**Base Mainnet**  
**December 2025**
