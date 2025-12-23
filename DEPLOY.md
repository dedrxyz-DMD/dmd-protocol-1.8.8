# DMD Protocol v1.8.8 - Base Mainnet Deployment

## Prerequisites

1. **Foundry installed** - https://book.getfoundry.sh/getting-started/installation
2. **ETH on Base** - Need ~0.01 ETH for deployment gas
3. **Private key** - Wallet with ETH on Base mainnet
4. **BaseScan API key** - For contract verification

## Environment Setup

Create a `.env` file:

```bash
# Required
PRIVATE_KEY=your_private_key_here
BASE_MAINNET_RPC_URL=https://mainnet.base.org

# Required for verification
BASESCAN_API_KEY=your_basescan_api_key
```

Load environment:
```bash
source .env
```

## Deploy to Base Mainnet

```bash
# Deploy all contracts
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Team Vesting Addresses (MAINNET)

| Role | Address | Allocation | % of Total | TGE (5%) |
|------|---------|------------|------------|----------|
| Foundation | `0x7c507141B182b337BEC960bAE0F53ED80b54D68a` | 1,800,000 DMD | 10% | 90,000 DMD |
| Founders | `0x3137e2508A9407143243887DFf3707C4A91077F2` | 900,000 DMD | 5% | 45,000 DMD |
| Developers | `0x1a7Cf64e6026d0b4ac7e113dEaA686D14c81D29C` | 450,000 DMD | 2.5% | 22,500 DMD |
| Contributors | `0xB03414CF7e2904f4e304e825D780dfE93a910B6C` | 450,000 DMD | 2.5% | 22,500 DMD |
| **Total** | - | **3,600,000 DMD** | **20%** | **180,000 DMD** |

## Post-Deployment Checklist

- [ ] All 6 contracts deployed successfully
- [ ] All contracts verified on BaseScan
- [ ] Save all contract addresses
- [ ] Team claims TGE via `vesting.claim()`
- [ ] Wait 7 days for first epoch
- [ ] Call `finalizeEpoch()` to start emissions
- [ ] Update website/dApp with contract addresses

## Contract Addresses (fill after deployment)

| Contract | Address |
|----------|---------|
| tBTC (external) | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |
| BTCReserveVault | `0x...` |
| EmissionScheduler | `0x...` |
| MintDistributor | `0x...` |
| DMDToken | `0x...` |
| RedemptionEngine | `0x...` |
| VestingContract | `0x...` |

## Network Info

- **Network**: Base Mainnet
- **Chain ID**: 8453
- **RPC**: https://mainnet.base.org
- **Explorer**: https://basescan.org

## Token Economics

```
MAX SUPPLY:        18,000,000 DMD
├── Emissions:     14,400,000 DMD (80%)
└── Team Vesting:   3,600,000 DMD (20%)

EMISSION SCHEDULE (25% annual decay):
├── Year 1:  3,600,000 DMD (69,230/week)
├── Year 2:  2,700,000 DMD (51,923/week)
├── Year 3:  2,025,000 DMD (38,942/week)
├── Year 4:  1,518,750 DMD (29,206/week)
└── ...until 14.4M cap reached

TEAM VESTING (5% TGE + 95% over 7 years):
├── Foundation:    1,800,000 DMD (10% of total) → TGE: 90,000 DMD
├── Founders:        900,000 DMD (5% of total)  → TGE: 45,000 DMD
├── Developers:      450,000 DMD (2.5% of total) → TGE: 22,500 DMD
└── Contributors:    450,000 DMD (2.5% of total) → TGE: 22,500 DMD
```

## Mainnet Operations

### 1. Claim Team TGE (Day 0)

Each team wallet can claim their TGE immediately after deployment:

```solidity
// From Foundation wallet
vesting.claim();  // Claims 90,000 DMD

// From Founders wallet
vesting.claim();  // Claims 45,000 DMD

// From Developers wallet
vesting.claim();  // Claims 22,500 DMD

// From Contributors wallet
vesting.claim();  // Claims 22,500 DMD
```

### 2. Finalize Epochs (Weekly)

Anyone can call this after 7 days:

```solidity
// Finalize single epoch
distributor.finalizeEpoch();

// Finalize multiple epochs (if behind)
distributor.finalizeMultipleEpochs(10);
```

### 3. Update Weight Cache (At Scale)

If >500 users, update cache before finalizing:

```solidity
// Process users in batches
vault.updateVestedWeightCache(0, 500);     // Users 0-499
vault.updateVestedWeightCache(500, 500);   // Users 500-999
// Continue until isComplete = true

// Then finalize epoch
distributor.finalizeEpoch();
```

### 4. User Operations

```solidity
// Lock tBTC (users)
tbtc.approve(vault, amount);
vault.lock(amount, lockMonths);  // 1-60 months

// Claim DMD (after epoch finalized)
distributor.claim(epochId);
distributor.claimMultiple([0, 1, 2, 3]);

// Redeem tBTC (after lock expires)
dmdToken.approve(redemption, requiredBurn);
redemption.redeem(positionId);
```

## Security Notes

- **No admin functions** - Protocol is fully immutable
- **No upgradability** - Contracts cannot be changed
- **No pause** - Cannot be stopped once deployed
- **Burn-to-redeem** - Must burn ALL DMD earned from position
- **Flash loan protected** - 7-day warmup + 3-day vesting
- **Audited** - 100/100 security score

## Important Reminders

1. **SAVE CONTRACT ADDRESSES** - They are permanent
2. **VERIFY ALL CONTRACTS** - Required for BaseScan interaction
3. **FIRST EPOCH IN 7 DAYS** - Cannot finalize before that
4. **TGE CLAIMABLE IMMEDIATELY** - Team can claim 5% at deployment
5. **NO RECOVERY** - Lost keys = lost funds (decentralized)
