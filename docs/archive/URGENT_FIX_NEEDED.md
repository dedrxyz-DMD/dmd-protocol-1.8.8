# URGENT: MintDistributor Test Mocks Need Update

## Current Status
**Tests Passing**: 221/234 (94.4%)
**Tests Failing**: 13 (all in MintDistributor.t.sol)

## What Was Fixed
1. ✅ `MintDistributor.sol` - Changed from `vault.totalWeightOf()` to `vault.getTotalVestedWeight()`
2. ✅ `IBTCReserveVault.sol` - Added `getTotalVestedWeight()` to interface
3. ✅ `BTCReserveVault.sol` - Already has the function implemented

## What Still Needs Fixing

### File: `test/MintDistributor.t.sol`

The `MockBTCReserveVault` needs to be updated to match the pattern already used successfully in the codebase.

**Lines to update (around line 15-26)**:

```solidity
contract MockBTCReserveVault {
    mapping(address => uint256) public totalWeightOf;
    mapping(address => uint256) public vestedWeightOf;  // ADD THIS
    uint256 public totalSystemWeight;

    function setUserWeight(address user, uint256 weight) external {
        totalWeightOf[user] = weight;
    }

    function setSystemWeight(uint256 weight) external {
        totalSystemWeight = weight;
    }

    // ADD THESE TWO FUNCTIONS:
    function getTotalVestedWeight(address user) external view returns (uint256) {
        return vestedWeightOf[user];
    }

    function setVestedWeight(address user, uint256 weight) external {
        vestedWeightOf[user] = weight;
    }
}
```

**Then replace all calls** (17 occurrences):
- Change: `vault.setUserWeight(...)`
- To: `vault.setVestedWeight(...)`

## Quick Fix Commands

```bash
cd ~/dmd-protocol-1.8

# Add the mapping
sed -i '16a\    mapping(address => uint256) public vestedWeightOf;' test/MintDistributor.t.sol

# Add getTotalVestedWeight function (after line 25)
sed -i '26a\    \n    function getTotalVestedWeight(address user) external view returns (uint256) {\n        return vestedWeightOf[user];\n    }\n\n    function setVestedWeight(address user, uint256 weight) external {\n        vestedWeightOf[user] = weight;\n    }' test/MintDistributor.t.sol

# Replace all setUserWeight calls with setVestedWeight
sed -i 's/vault\.setUserWeight(/vault.setVestedWeight(/g' test/MintDistributor.t.sol

# Test
forge test --match-path test/MintDistributor.t.sol
```

## Why This Fix Is Critical

Without this fix, **the flash loan protection is bypassed** because:
- MintDistributor was using raw `totalWeightOf()` which includes ALL weight
- It needs to use `getTotalVestedWeight()` which respects the 7-day delay + 3-day warmup
- Attackers could flash loan massive BTC, get huge weight, and steal emissions

## Expected Result After Fix

All 234 tests should pass, including:
- MintDistributor tests (currently failing)
- WeightWarmup tests
- RedTeam attack tests showing flash loans are defeated

## Reference

This exact pattern was already successfully applied to fix similar issues earlier. See the working implementation in other test files that use vested weights correctly.
