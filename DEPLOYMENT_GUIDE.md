# DMD Protocol v1.8.8 - Deployment Guide

## Prerequisites

### 1. Install Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Get Base Sepolia ETH
- Visit: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
- Or: https://faucet.quicknode.com/base/sepolia
- You need at least 0.05 ETH for deployment

### 3. Get Basescan API Key
- Create account at: https://basescan.org
- Go to API Keys section
- Create new API key

---

## Environment Setup

### Create `.env` file in project root:

```bash
# Your deployer private key (DO NOT COMMIT!)
PRIVATE_KEY=your_private_key_here

# Basescan API key for verification
BASESCAN_API_KEY=your_basescan_api_key_here

# Optional: Custom RPC (if public is slow)
BASE_SEPOLIA_RPC=https://sepolia.base.org
BASE_MAINNET_RPC=https://mainnet.base.org
```

**IMPORTANT:** Add `.env` to `.gitignore`:
```bash
echo ".env" >> .gitignore
```

---

## Deployment Steps

### Step 1: Install Dependencies
```bash
cd dmd-protocol-1.8.8
forge install
```

### Step 2: Compile Contracts
```bash
forge build
```

Expected output:
```
[⠊] Compiling...
[⠒] Compiling 15 files with 0.8.20
[⠑] Solc 0.8.20 finished in 2.5s
Compiler run successful!
```

### Step 3: Run Tests (Optional but Recommended)
```bash
forge test -vvv
```

### Step 4: Deploy to Base Sepolia (Testnet)
```bash
source .env

forge script script/DeployDMDFresh.s.sol:DeployDMDFresh \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --verify \
  -vvvv
```

### Step 5: Deploy to Base Mainnet (Production)
```bash
source .env

forge script script/DeployDMDFresh.s.sol:DeployDMDFresh \
  --sig "runMainnet()" \
  --rpc-url https://mainnet.base.org \
  --broadcast \
  --verify \
  -vvvv
```

---

## Contract Verification

If automatic verification fails, verify manually:

### BTCReserveVault
```bash
forge verify-contract \
  --chain base-sepolia \
  --constructor-args $(cast abi-encode "constructor(address,address)" TBTC_ADDRESS REDEMPTION_ADDRESS) \
  VAULT_ADDRESS \
  src/BTCReserveVault.sol:BTCReserveVault
```

### DMDToken
```bash
forge verify-contract \
  --chain base-sepolia \
  --constructor-args $(cast abi-encode "constructor(address)" DISTRIBUTOR_ADDRESS) \
  TOKEN_ADDRESS \
  src/DMDToken.sol:DMDToken
```

### All Other Contracts
Repeat pattern for:
- EmissionScheduler
- MintDistributor
- RedemptionEngine
- VestingContract

---

## Post-Deployment Checklist

### 1. Verify All Contracts on Basescan
- [ ] BTCReserveVault - verified
- [ ] DMDToken - verified
- [ ] EmissionScheduler - verified
- [ ] MintDistributor - verified
- [ ] RedemptionEngine - verified
- [ ] VestingContract - verified

### 2. Verify Contract Linkages
```bash
# Check vault's tBTC address
cast call VAULT_ADDRESS "TBTC()" --rpc-url https://sepolia.base.org

# Check vault's redemption engine
cast call VAULT_ADDRESS "redemptionEngine()" --rpc-url https://sepolia.base.org

# Check token's mint distributor
cast call TOKEN_ADDRESS "mintDistributor()" --rpc-url https://sepolia.base.org
```

### 3. Verify Emissions Started
```bash
# Check emission start time
cast call SCHEDULER_ADDRESS "emissionStartTime()" --rpc-url https://sepolia.base.org

# Check distribution start time
cast call DISTRIBUTOR_ADDRESS "distributionStartTime()" --rpc-url https://sepolia.base.org
```

---

## Testing Flow on Testnet

### 1. Get Test tBTC (Testnet Only)
The deployment mints 100 MockTBTC to deployer. For additional:
```bash
cast send MOCK_TBTC_ADDRESS "mint(address,uint256)" YOUR_ADDRESS 1000000000000000000 --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

### 2. Approve Vault
```bash
cast send MOCK_TBTC_ADDRESS "approve(address,uint256)" VAULT_ADDRESS 1000000000000000000 --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

### 3. Lock tBTC
```bash
# Lock 1 tBTC for 12 months
cast send VAULT_ADDRESS "lock(uint256,uint256)" 1000000000000000000 12 --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

### 4. Check Position
```bash
cast call VAULT_ADDRESS "getPosition(address,uint256)" YOUR_ADDRESS 0 --rpc-url https://sepolia.base.org
```

### 5. Wait for Vesting (10 days on testnet)
- 7 days warmup (weight = 0)
- 3 days linear vesting
- After 10 days: full weight

### 6. Check Vested Weight
```bash
cast call VAULT_ADDRESS "getVestedWeight(address)" YOUR_ADDRESS --rpc-url https://sepolia.base.org
```

### 7. Finalize Epoch (After 7 days)
```bash
cast send DISTRIBUTOR_ADDRESS "finalizeEpoch()" --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

### 8. Claim Rewards
```bash
cast send DISTRIBUTOR_ADDRESS "claim(uint256)" 0 --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

---

## Deployed Contract Addresses

After deployment, update these in the website (`index.html`):

### Base Sepolia (Testnet)
```javascript
const CONFIG = {
    CHAIN_ID: 84532,  // Base Sepolia
    TBTC_ADDRESS: 'MOCK_TBTC_ADDRESS',
    DMD_TOKEN_ADDRESS: 'TOKEN_ADDRESS',
    VAULT_ADDRESS: 'VAULT_ADDRESS',
    DISTRIBUTOR_ADDRESS: 'DISTRIBUTOR_ADDRESS',
    REDEMPTION_ADDRESS: 'REDEMPTION_ADDRESS',
};
```

### Base Mainnet (Production)
```javascript
const CONFIG = {
    CHAIN_ID: 8453,  // Base Mainnet
    TBTC_ADDRESS: '0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b',  // Real tBTC
    DMD_TOKEN_ADDRESS: 'DEPLOYED_ADDRESS',
    VAULT_ADDRESS: 'DEPLOYED_ADDRESS',
    DISTRIBUTOR_ADDRESS: 'DEPLOYED_ADDRESS',
    REDEMPTION_ADDRESS: 'DEPLOYED_ADDRESS',
};
```

---

## Security Reminders

1. **Never commit private keys** - Use environment variables
2. **Verify all contracts** - Transparency is critical for trust
3. **Test on Sepolia first** - Full test cycle before mainnet
4. **Save deployment addresses** - They're in `deployments/` folder
5. **Double-check tBTC address** - Must be correct for mainnet

---

## Troubleshooting

### "Insufficient funds"
Get more ETH from faucet or bridge from another network.

### "Nonce too low"
```bash
# Reset nonce tracking
rm -rf broadcast/
```

### "Contract already verified"
Already verified - check on Basescan.

### "REVERT: Unauthorized"
Check that you're calling with the correct account (owner for initialization functions).

### Gas estimation fails
Add explicit gas limit:
```bash
forge script ... --gas-limit 5000000
```

---

## Support

- GitHub Issues: https://github.com/dedrxyz-DMD/dmd-protocol-1.8.8/issues
- Security Audit: See `SECURITY_AUDIT_FINAL.md`
- Whitepaper: See `WHITEPAPER.md`
