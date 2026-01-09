# DMD Protocol User Guide

> A step-by-step guide to locking tBTC, earning DMD rewards, and redeeming your tBTC

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Setup: Connecting to Base Network](#setup-connecting-to-base-network)
4. [Getting tBTC on Base](#getting-tbtc-on-base)
5. [Locking tBTC to Earn DMD](#locking-tbtc-to-earn-dmd)
6. [Claiming Your DMD Rewards](#claiming-your-dmd-rewards)
7. [Unlocking Your tBTC](#unlocking-your-tbtc)
8. [Understanding Lock Durations and Weight](#understanding-lock-durations-and-weight)
9. [Early Unlock Option](#early-unlock-option)
10. [Important Notes and Best Practices](#important-notes-and-best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Overview

DMD Protocol allows you to:
- **Lock tBTC** (Threshold Network Bitcoin) on Base chain
- **Earn DMD tokens** based on your locked amount and duration
- **Redeem your tBTC** by burning the DMD you earned from that position

The protocol operates on an **Extreme Deflationary Digital Asset (EDAD)** mechanism where you must burn 100% of earned DMD to unlock your tBTC.

---

## Prerequisites

Before you begin, you'll need:

- **MetaMask wallet** (or any Web3 wallet compatible with Base)
- **Some ETH on Base** for gas fees (approximately $5-10 worth)
- **tBTC tokens** to lock (minimum recommended: 0.01 tBTC)

---

## Setup: Connecting to Base Network

### Step 1: Install MetaMask

If you don't have MetaMask installed:

1. Visit [metamask.io](https://metamask.io)
2. Download and install the browser extension
3. Create a new wallet or import an existing one
4. **Save your seed phrase securely** - you'll need it to recover your wallet

### Step 2: Add Base Network to MetaMask

Base is an Ethereum Layer 2 network. To add it:

**Option A: Automatic (Recommended)**
1. Visit [chainlist.org](https://chainlist.org)
2. Search for "Base"
3. Click "Connect Wallet"
4. Click "Add to MetaMask"

**Option B: Manual**
1. Open MetaMask
2. Click the network dropdown (top center)
3. Click "Add Network" → "Add a network manually"
4. Enter the following details:

```
Network Name: Base
RPC URL: https://mainnet.base.org
Chain ID: 8453
Currency Symbol: ETH
Block Explorer: https://basescan.org
```

5. Click "Save"
6. Switch to Base network

### Step 3: Verify Network Connection

- Open MetaMask
- Ensure "Base" is selected in the network dropdown
- You should see your ETH balance (will be 0 if you haven't deposited yet)

---

## Getting tBTC on Base

You need tBTC tokens on Base to lock in the DMD Protocol. Here's how to get them:

### Option 1: Bridge tBTC from Ethereum

If you have tBTC on Ethereum mainnet:

1. Visit the official Base Bridge: [bridge.base.org](https://bridge.base.org)
2. Connect your MetaMask wallet
3. Select tBTC token
4. Enter the amount to bridge
5. Click "Deposit to Base"
6. Confirm the transaction in MetaMask
7. Wait 10-20 minutes for the bridge to complete

**tBTC Contract Address on Ethereum**: `0x18084fbA666a33d37592fA2633fD49a74DD93a88`
**tBTC Contract Address on Base**: `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`

### Option 2: Buy ETH and Swap to tBTC

If you don't have tBTC:

1. **Get ETH on Base:**
   - Transfer ETH from Ethereum L1 using [bridge.base.org](https://bridge.base.org)
   - Or buy directly on Base using a CEX that supports Base withdrawals (Coinbase, Binance)

2. **Swap ETH to tBTC:**
   - Visit a DEX on Base (e.g., [Uniswap](https://app.uniswap.org), [Aerodrome](https://aerodrome.finance))
   - Connect MetaMask
   - Select ETH → tBTC
   - Enter amount to swap
   - Review slippage (recommended: 0.5% - 1%)
   - Click "Swap"
   - Confirm transaction in MetaMask

3. **Verify tBTC Balance:**
   - Open MetaMask
   - Click "Assets" → "Import tokens"
   - Enter tBTC contract: `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`
   - tBTC should appear in your wallet

---

## Locking tBTC to Earn DMD

Once you have tBTC on Base, you're ready to lock it and start earning DMD.

### Step 1: Visit the DMD Protocol Dashboard

1. Navigate to the DMD Protocol app (URL provided by DMD Foundation)
2. Click "Connect Wallet"
3. Select MetaMask
4. Approve the connection
5. Ensure you're on Base network

### Step 2: Approve tBTC Spending

Before locking, you must approve the BTCReserveVault contract to spend your tBTC:

1. Go to the "Lock" section
2. Enter the amount of tBTC you want to lock
3. Select lock duration (1-60 months)
4. Click "Approve tBTC"
5. **MetaMask will pop up** - confirm the approval transaction
6. Wait for confirmation (usually 1-5 seconds on Base)

**BTCReserveVault Address**: `0x02A2cC006FB2F0b4B59Dd30EA6613eE2BA84942E`

### Step 3: Lock Your tBTC

1. After approval completes, click "Lock tBTC"
2. **MetaMask will pop up** - review the transaction:
   - Amount of tBTC being locked
   - Gas fee (should be $0.05-$0.50)
3. Click "Confirm"
4. Wait for transaction confirmation
5. You'll receive a Position ID - **save this for your records**

### Step 4: Understand Your Position

After locking, you'll see:

- **Position ID**: Your unique position number (starts at 0)
- **Amount Locked**: How much tBTC you locked
- **Lock Duration**: Months your tBTC is locked
- **Unlock Date**: When you can redeem (if no early unlock)
- **Weight**: Your earning power (higher = more DMD)
- **Vesting Status**: Weight vesting progress (Days 0-10)

---

## Claiming Your DMD Rewards

DMD emissions are distributed in 7-day epochs. Here's how to claim:

### Step 1: Wait for Weight to Vest

Your locked tBTC doesn't earn rewards immediately (flash loan protection):

- **Days 0-7**: Warmup period - 0% weight active
- **Days 7-10**: Vesting period - weight increases from 0% to 100%
- **Day 10+**: Full weight active - earning maximum rewards

### Step 2: Check Claimable DMD

1. Go to the "Claim" section of the dashboard
2. You'll see:
   - **Total DMD Earned**: All-time earnings from your position(s)
   - **Claimable Now**: DMD ready to claim this epoch
   - **Next Epoch**: Time until next distribution

### Step 3: Claim Your DMD

1. Click "Claim DMD Rewards"
2. **MetaMask will pop up** - confirm the transaction
3. Wait for confirmation
4. DMD tokens will appear in your wallet

### Step 4: Add DMD to MetaMask

To see your DMD balance:

1. Open MetaMask
2. Click "Assets" → "Import tokens"
3. Enter DMD contract: `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f`
4. Click "Add custom token"
5. Your DMD balance will now be visible

**DMD Token Details:**
- **Name**: DMD Protocol
- **Symbol**: DMD
- **Decimals**: 18
- **Contract**: `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f`

---

## Unlocking Your tBTC

To unlock your tBTC, you must **burn 100% of the DMD earned from that position**.

### Step 1: Wait for Unlock Time

Check your position status:

- **Locked**: Cannot redeem yet
- **Unlocked**: Lock period has passed, ready to redeem

### Step 2: Ensure You Have Enough DMD

Before redeeming:

1. Go to the "Redeem" section
2. Select your position
3. View "DMD Required to Burn"
4. **Important**: You must have at least this amount of DMD in your wallet

**If you sold or transferred your DMD:**
- You'll need to buy it back before you can unlock your tBTC
- The protocol enforces this rule - there are no exceptions

### Step 3: Approve DMD Spending

1. In the "Redeem" section, click "Approve DMD"
2. **MetaMask will pop up** - confirm the approval
3. This allows the RedemptionEngine to burn your DMD
4. Wait for confirmation

**RedemptionEngine Address**: `0x70538c1067199834807d00BBCBE81246b305eB51`

### Step 4: Burn DMD and Redeem tBTC

1. Click "Redeem tBTC"
2. **MetaMask will pop up** - confirm the transaction
3. The contract will:
   - Transfer the required DMD from your wallet
   - **Burn it permanently** (DMD is destroyed)
   - Return your tBTC to your wallet
4. Wait for confirmation
5. Your tBTC is now back in your wallet

### Example Redemption Flow

Let's say you locked 1 tBTC for 12 months:

1. **Month 0**: Lock 1 tBTC → receive Position #0
2. **Months 0-12**: Earn DMD (let's say 500 DMD total)
3. **Month 12**: Position unlocks
4. **Redemption**:
   - You need 500 DMD to redeem
   - You have 500 DMD in wallet
   - You approve RedemptionEngine to spend DMD
   - You call redeem → 500 DMD burned → 1 tBTC returned

**If you only have 300 DMD:**
- Transaction will fail
- You need to acquire 200 more DMD
- Options: buy on DEX, wait to earn more from other positions

---

## Understanding Lock Durations and Weight

Lock duration affects your earning potential through a **weight multiplier**.

### Weight Formula

```
Weight = Amount × (1 + min(lockMonths, 24) × 0.02)
```

### Weight Multipliers by Duration

| Lock Duration | Multiplier | Example (1 tBTC) |
|---------------|------------|------------------|
| 1 month       | 1.02×      | 1.02 weight      |
| 6 months      | 1.12×      | 1.12 weight      |
| 12 months     | 1.24×      | 1.24 weight      |
| 18 months     | 1.36×      | 1.36 weight      |
| 24 months     | 1.48×      | 1.48 weight      |
| 36 months     | 1.48×      | 1.48 weight (capped) |
| 60 months     | 1.48×      | 1.48 weight (capped) |

**Key Points:**
- Bonus caps at 24 months (48% increase)
- You can lock up to 60 months, but bonus doesn't increase beyond 24
- Longer locks still provide advantages (no need to re-lock)

### Choosing Lock Duration

**Short Lock (1-6 months):**
- Lower weight multiplier
- More flexibility
- Good for testing the protocol
- Can withdraw sooner

**Medium Lock (12-18 months):**
- Balanced multiplier (1.24× - 1.36×)
- Reasonable commitment
- Good for active participants

**Long Lock (24+ months):**
- Maximum weight multiplier (1.48×)
- Set and forget strategy
- Best for long-term holders
- Note: Bonus caps at 24 months

---

## Early Unlock Option

Need your tBTC before the lock period ends? You can request early unlock.

### How Early Unlock Works

1. **Request early unlock** → your weight is removed immediately (stop earning)
2. **Wait 30 days** → mandatory cooldown period
3. **Redeem** → burn earned DMD and get tBTC back

### Step-by-Step: Early Unlock

#### Step 1: Request Early Unlock

1. Go to your position in the dashboard
2. Click "Request Early Unlock"
3. **Warning**: You'll stop earning DMD immediately
4. **MetaMask will pop up** - confirm transaction
5. Note the unlock date (current time + 30 days)

#### Step 2: Wait 30 Days

- Your position status will show "Early Unlock Pending"
- You're no longer earning DMD rewards
- You can cancel during this time to restore earning

#### Step 3: Cancel (Optional)

If you change your mind:

1. Click "Cancel Early Unlock"
2. **MetaMask will pop up** - confirm transaction
3. Your weight is restored
4. You resume earning DMD

#### Step 4: Redeem After 30 Days

Once 30 days pass:

1. Follow the normal redemption process:
   - Approve DMD spending
   - Burn required DMD
   - Receive tBTC back

### Example: Early Unlock Timeline

**Day 0**: Lock 1 tBTC for 24 months
**Day 180** (6 months later): Request early unlock
- Stop earning immediately
- Earned ~200 DMD so far

**Day 210** (30 days later): Early unlock ready
- Burn 200 DMD
- Get 1 tBTC back

**Comparison to Normal Unlock:**
- Normal: Wait 24 months (Day 720)
- Early: Day 210 (saved 17 months)
- Trade-off: Earned less DMD (200 vs ~800)

---

## Important Notes and Best Practices

### Critical Rules

1. **You MUST burn 100% of earned DMD to redeem tBTC**
   - No partial redemptions
   - No governance exceptions
   - Plan accordingly before selling DMD

2. **Weight takes 10 days to fully vest**
   - Days 0-7: No earnings
   - Days 7-10: Partial earnings
   - Day 10+: Full earnings

3. **Gas fees required for all transactions**
   - Approvals: ~$0.10-$0.50
   - Locks: ~$0.50-$2.00
   - Claims: ~$0.30-$1.00
   - Redemptions: ~$0.50-$2.00

4. **Lock duration is permanent**
   - Cannot extend or shorten
   - Early unlock has 30-day penalty
   - Choose duration carefully

### Best Practices

#### Before Locking

- Start with a small test lock (0.01-0.1 tBTC)
- Understand the redemption requirement
- Calculate expected DMD earnings
- Choose lock duration based on your timeline
- Keep extra ETH for gas fees

#### Managing Positions

- Track your Position IDs
- Screenshot your lock confirmation
- Monitor DMD earned regularly
- Don't sell ALL your DMD (keep enough for redemption)
- Consider locking in multiple positions for flexibility

#### Before Selling DMD

Ask yourself:
- How much DMD have I earned from each position?
- Will I need this DMD to redeem tBTC later?
- Should I sell from earlier positions first?

**Pro tip**: Create a spreadsheet tracking:
- Position ID
- tBTC locked
- Lock date
- Unlock date
- DMD earned
- DMD needed for redemption

#### Security

- Never share your seed phrase
- Use a hardware wallet for large amounts
- Verify contract addresses before approving
- Bookmark the official DMD Protocol dashboard
- Be wary of phishing sites

---

## Troubleshooting

### "Transaction Failed: Insufficient Balance"

**Problem**: Not enough ETH for gas fees
**Solution**:
- Bridge more ETH to Base
- Check your ETH balance covers gas estimate

### "Transaction Failed: Transfer Amount Exceeds Allowance"

**Problem**: Haven't approved token spending
**Solution**:
- Click "Approve" first (tBTC for locking, DMD for redeeming)
- Wait for approval to confirm
- Then retry the main transaction

### "Transaction Failed: Position Still Locked"

**Problem**: Trying to redeem before unlock time
**Solution**:
- Check your position unlock date
- Wait until lock period expires
- Or request early unlock (30-day wait)

### "Transaction Failed: Insufficient DMD Balance"

**Problem**: Don't have enough DMD to burn for redemption
**Solution**:
- Check required DMD amount
- Claim pending rewards
- Buy more DMD on a DEX if needed
- Or wait to earn more from other positions

### "Weight Not Increasing"

**Problem**: Expected to see weight immediately after locking
**Solution**:
- This is normal! 7-day warmup period
- Weight starts vesting on Day 7
- Full weight active on Day 10
- Be patient

### "Can't See DMD in Wallet"

**Problem**: Claimed DMD but don't see it
**Solution**:
- Add DMD token to MetaMask manually
- Contract: `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f`
- Symbol: DMD, Decimals: 18

### "Can't Connect to Base Network"

**Problem**: MetaMask not showing Base
**Solution**:
- Add Base network manually (see setup section)
- RPC: `https://mainnet.base.org`
- Chain ID: `8453`
- Switch to Base in network dropdown

### "Transaction Taking Too Long"

**Problem**: Transaction pending for 5+ minutes
**Solution**:
- Base transactions usually confirm in seconds
- Check [BaseScan](https://basescan.org) for your transaction
- If stuck, try speeding up in MetaMask
- If failed, retry with higher gas

---

## Contract Addresses (Base Mainnet)

For verification and direct contract interaction:

| Contract | Address |
|----------|---------|
| **BTCReserveVault** | `0x02A2cC006FB2F0b4B59Dd30EA6613eE2BA84942E` |
| **DMDToken** | `0x2b795f885Ccf84090c6DaFd2d03Fc03807A0625f` |
| **RedemptionEngine** | `0x70538c1067199834807d00BBCBE81246b305eB51` |
| **MintDistributor** | `0x08EBc0cE45eC551f0Ad3584538A0DF287F169b5c` |
| **tBTC (External)** | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |

**Verify on BaseScan**: [basescan.org](https://basescan.org)

---

## Summary Checklist

### Initial Setup
- [ ] Install MetaMask
- [ ] Add Base network
- [ ] Get ETH on Base for gas
- [ ] Get tBTC on Base

### Locking Process
- [ ] Connect wallet to DMD Protocol dashboard
- [ ] Approve tBTC spending
- [ ] Lock tBTC with chosen duration
- [ ] Save Position ID
- [ ] Wait 10 days for full weight vesting

### Earning & Claiming
- [ ] Monitor DMD earned in dashboard
- [ ] Claim rewards after each epoch (7 days)
- [ ] Add DMD token to MetaMask
- [ ] Track total DMD earned per position

### Redemption Process
- [ ] Wait for unlock date (or request early unlock + 30 days)
- [ ] Verify you have enough DMD to burn
- [ ] Approve DMD spending for RedemptionEngine
- [ ] Redeem position (burns DMD, returns tBTC)
- [ ] Verify tBTC received in wallet

---

## Need Help?

- **Protocol Documentation**: See `README.md` and `DMD_Protocol_Whitepaper_v1.8.8.md`
- **Smart Contracts**: Source code in `/src` directory
- **Security Audits**: See `/Audit_Report` directory
- **BaseScan Explorer**: [basescan.org](https://basescan.org)

---

**DMD Protocol v1.8.8**
Immutable • Bitcoin-backed • Structurally Deflationary

*This guide is for educational purposes. The DMD Protocol is fully immutable with no admin keys, upgrades, or governance. All rules are enforced by smart contracts. Users are responsible for understanding the redemption requirements before locking tBTC.*
