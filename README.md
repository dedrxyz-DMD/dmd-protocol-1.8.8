# DMD Protocol v1.8 - tBTC Only

> tBTC Locking Protocol on Base Mainnet with Flash Loan Protection

**Status**: Production Ready | **Tests**: 160/160 passing (100%) | **Chain**: Base Mainnet

---

## Overview

DMD Protocol is a decentralized system for locking tBTC (Threshold Network Bitcoin) on Base L2 to earn DMD token emissions. The protocol is permanently immutable with NO governance, NO upgrades, and accepts ONLY tBTC.

### Key Features

- **Single Asset**: ONLY tBTC on Base mainnet (0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b)
- **Permanently Immutable**: No governance, no setters, no upgrades, no multi-sig
- **Flash Loan Protection**: 10-day activation period prevents attack vectors
- **Time-Weighted Rewards**: Lock duration multipliers (1.0x to 1.48x)
- **Emissions Decay**: 18% annual reduction with 18M DMD max supply
- **Fully Audited**: 160 comprehensive tests passing

---

## Architecture

### Core Contracts

- BTCReserveVault.sol: tBTC locking and weight tracking (~400 LOC)
- MintDistributor.sol: Epoch-based reward distribution (~270 LOC)
- EmissionScheduler.sol: 18% decay emissions schedule (~220 LOC)
- DMDToken.sol: ERC20 DMD token (~160 LOC)
- RedemptionEngine.sol: tBTC withdrawal logic (~200 LOC)
- VestingContract.sol: Team token vesting (~280 LOC)

**tBTC Address (Base Mainnet)**: 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b

### Security Model

**Flash Loan Protection (10-day activation)**:
- Days 0-7: Epoch delay (0% weight)
- Days 7-10: Linear vesting (0% to 100% weight)
- Day 10+: Full weight activated

**Security Fixes Applied**:
- HIGH-1: Division by zero prevention (NoActivePositions error)
- HIGH-2: Gas DoS prevention (MAX_POSITIONS_PER_USER = 100)

---

## Quick Start

Install Foundry, clone the repo, run forge build and forge test.

---

## Test Coverage

160 tests passing:
- BTCReserveVault: tBTC locking, weights, vesting
- MintDistributor: 33 tests (claims, epochs)
- EmissionScheduler: 36 tests (decay schedule)
- DMDToken: 28 tests (ERC20 functionality)
- RedemptionEngine: 26 tests (unlocks, redemptions)
- VestingContract: 37 tests (team vesting)

---

## Security Considerations

Audited attack vectors:
1. Flash Loan Attacks: Prevented by 10-day activation
2. Reentrancy: CEI pattern throughout
3. Front-Running: Epoch-based system
4. Weight Gaming: Vesting enforces time-weighted rewards
5. Division by Zero: Protected
6. Gas DoS: Position limits

### Immutability Guarantees

- No upgrades
- No governance
- tBTC address hardcoded
- No pauses
- No multi-sig control

---

## Version Info

- **Version**: 1.8 (tBTC-only)
- **Date**: December 16, 2025
- **Solidity**: 0.8.20
- **Network**: Base Mainnet
- **Tests**: 160/160 passing

**Ready for mainnet deployment on Base L2.**
