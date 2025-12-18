# DMD Protocol v1.8.8 - Base Mainnet Deployment

## Prerequisites

1. **Foundry installed** - https://book.getfoundry.sh/getting-started/installation
2. **ETH on Base** - Need ~0.005 ETH for deployment gas
3. **Private key** - Wallet with ETH on Base mainnet

## Environment Setup

Create a `.env` file:

```bash
# Required
PRIVATE_KEY=your_private_key_here
BASE_MAINNET_RPC_URL=https://mainnet.base.org

# Optional (for contract verification)
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

## Verify Contracts (if not auto-verified)

```bash
# BTCReserveVault
forge verify-contract <VAULT_ADDRESS> src/BTCReserveVault.sol:BTCReserveVault \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address)" 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b <REDEMPTION_ADDRESS>)

# EmissionScheduler
forge verify-contract <SCHEDULER_ADDRESS> src/EmissionScheduler.sol:EmissionScheduler \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address)" <DISTRIBUTOR_ADDRESS>)

# MintDistributor
forge verify-contract <DISTRIBUTOR_ADDRESS> src/MintDistributor.sol:MintDistributor \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" <TOKEN_ADDRESS> <VAULT_ADDRESS> <SCHEDULER_ADDRESS>)

# DMDToken
forge verify-contract <TOKEN_ADDRESS> src/DMDToken.sol:DMDToken \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address)" <DISTRIBUTOR_ADDRESS> <VESTING_ADDRESS>)

# RedemptionEngine
forge verify-contract <REDEMPTION_ADDRESS> src/RedemptionEngine.sol:RedemptionEngine \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" <TOKEN_ADDRESS> <VAULT_ADDRESS> <DISTRIBUTOR_ADDRESS>)

# VestingContract
forge verify-contract <VESTING_ADDRESS> src/VestingContract.sol:VestingContract \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address[],uint256[])" <TOKEN_ADDRESS> "[<DEPLOYER>]" "[3600000000000000000000000]")
```

## Post-Deployment Checklist

- [ ] All contracts deployed successfully
- [ ] Contracts verified on BaseScan
- [ ] Test lock() with small tBTC amount
- [ ] Test finalizeEpoch() after 7 days
- [ ] Test claim() functionality
- [ ] Update website with contract addresses

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
├── Year 1:  3,600,000 DMD
├── Year 2:  2,700,000 DMD
├── Year 3:  2,025,000 DMD
├── Year 4:  1,518,750 DMD
└── ...until 14.4M cap

TEAM VESTING:
├── TGE:     180,000 DMD (5%)
└── Linear:  3,420,000 DMD over 7 years
```

## Security Notes

- **No admin functions** - Protocol is fully immutable
- **No upgradability** - Contracts cannot be changed
- **No pause** - Cannot be stopped once deployed
- **Burn-to-redeem** - Must burn ALL DMD from position to get tBTC back
