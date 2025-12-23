# DMD Protocol v1.8.8 - Deployment Guide

## Overview

This guide covers deploying the DMD Protocol to Base Sepolia testnet and Base mainnet.

**Protocol Features:**
- tBTC-only (immutable, no other BTC variants)
- Fully decentralized (no owner, admin, or governance)
- Emissions auto-start at deployment
- Flash loan protection (7-day warmup + 3-day vesting)

## Prerequisites

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Install Dependencies

```bash
forge install
```

### 3. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your values:

```env
PRIVATE_KEY=your_private_key_without_0x
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASE_MAINNET_RPC_URL=https://mainnet.base.org
BASESCAN_API_KEY=your_basescan_api_key
```

### 4. Fund Deployer Wallet

- **Testnet:** Get Base Sepolia ETH from [Base Faucet](https://www.alchemy.com/faucets/base-sepolia)
- **Mainnet:** Ensure you have sufficient ETH for gas (~0.05 ETH recommended)

## Deployment Commands

### Deploy to Base Sepolia Testnet

```bash
# Load environment variables
source .env

# Run deployment
forge script script/DeployDMDFresh.s.sol:DeployDMDFresh \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### Deploy to Base Mainnet (Production)

**IMPORTANT:** For mainnet, you must modify the deployment script to use the real tBTC address instead of MockTBTC.

1. Edit `script/DeployDMDFresh.s.sol`:
   - Remove MockTBTC deployment
   - Use `MAINNET_TBTC = 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`

2. Run deployment:

```bash
forge script script/DeployDMDFresh.s.sol:DeployDMDFresh \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Contract Addresses

After deployment, addresses are saved to:
- `deployments/testnet-deployment.env`

## Verification

Contracts are auto-verified during deployment with the `--verify` flag.

To manually verify:

```bash
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \
  --chain base-sepolia \
  --etherscan-api-key $BASESCAN_API_KEY
```

## Post-Deployment Testing

### 1. Mint Test tBTC (Testnet Only)

```solidity
MockTBTC(tbtcAddress).mint(yourAddress, 10e18);  // 10 tBTC
```

### 2. Lock tBTC

```solidity
// Approve vault
IERC20(tbtcAddress).approve(vaultAddress, amount);

// Lock for 12 months
BTCReserveVault(vaultAddress).lock(amount, 12);
```

### 3. Wait for Weight Vesting

- 7 days warmup (no weight)
- 3 days linear vesting
- Full weight after 10 days

### 4. Finalize Epoch

```solidity
MintDistributor(distributorAddress).finalizeEpoch();
```

### 5. Claim DMD

```solidity
MintDistributor(distributorAddress).claim(epochId);
```

## Contract Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DMD Protocol v1.8.8                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────────┐                      │
│  │   MockTBTC   │     │  BTCReserveVault │                      │
│  │  (testnet)   │────▶│   (tBTC locking) │                      │
│  └──────────────┘     └────────┬─────────┘                      │
│                                │                                 │
│                                │ weight                          │
│                                ▼                                 │
│  ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐ │
│  │  Emission    │────▶│  MintDistributor │────▶│   DMDToken   │ │
│  │  Scheduler   │     │   (epoch mgmt)   │     │  (ERC20)     │ │
│  └──────────────┘     └────────┬─────────┘     └──────┬───────┘ │
│                                │                       │         │
│                                │                       │         │
│                                ▼                       ▼         │
│                       ┌──────────────────┐    ┌──────────────┐  │
│                       │ RedemptionEngine │    │   Vesting    │  │
│                       │  (burn to unlock)│    │  Contract    │  │
│                       └──────────────────┘    └──────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Security Features

| Feature | Description |
|---------|-------------|
| Flash Loan Protection | 7-day warmup + 3-day vesting before weight counts |
| No Admin Controls | Fully decentralized, immutable after deployment |
| CEI Pattern | All external calls made after state changes |
| Hard Emission Cap | 14.4M DMD maximum ever minted |
| Immutable tBTC | Token address cannot be changed after deployment |

## Gas Estimates

| Operation | Estimated Gas |
|-----------|--------------|
| Deploy All Contracts | ~3,000,000 |
| lock() | ~150,000 |
| finalizeEpoch() | ~100,000 |
| claim() | ~80,000 |
| redeem() | ~120,000 |

## Troubleshooting

### "Address mismatch" error
The deployment uses CREATE address prediction. Ensure no transactions are made between starting the script.

### "Need at least 0.01 ETH" error
Fund your deployer wallet with testnet/mainnet ETH.

### Verification fails
Wait a few minutes after deployment, then retry verification manually.

## Support

For issues or questions, open an issue on the repository.
