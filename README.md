# Cross-Chain Rebase Token Protocol

This project implements a cross-chain rebase token integrated with **Chainlink CCIP (Cross-Chain Interoperability Protocol)** to allow users to seamlessly bridge their tokens across multiple chains while preserving their personalized interest rates.

---

## **Key Features**

### **1. Rebase Token with Decreasing Interest Rate**
- The `RebaseToken` contract is an ERC20 token with an interest-bearing mechanism.
- Each user has a personal interest rate, fixed at the global rate at the time of deposit.
- The global interest rate can only **decrease over time**, ensuring early users are rewarded with higher interest rates.
- Users can transfer tokens while maintaining accrued interest.

---

### **2. Vault**
- Users deposit **ETH** into the `Vault` contract to receive **Rebase Tokens** in return.
- The deposited ETH is stored as **protocol collateral**, and users can redeem their ETH by burning Rebase Tokens.
- Rewards (**protocol incentives**) can be added to the vault, enhancing early participation benefits.

---

### **3. Rebase Token Pool (Cross-Chain Pool)**
- The `RebaseTokenPool` integrates with **Chainlink CCIP** to facilitate cross-chain bridging of Rebase Tokens.
- When a user bridges tokens to another chain:
  - Their **interest rate is preserved**.
  - Tokens are burned on the source chain and minted on the destination chain with the same interest rate.
- This ensures a **seamless multi-chain user experience** while maintaining yield consistency.

---

### **4. Chainlink CCIP Integration**
- The protocol uses **Chainlink CCIP** to securely bridge assets across chains.
- The `BridgeTokenScript` automates the cross-chain transfer process:
  - Approves tokens and LINK fees.
  - Sends CCIP messages with **encoded user data (including interest rates).**

---

### **5. Rewards & Incentives**
- **Early users benefit from higher interest rates** before rate reductions.
- Users who bridge to **Layer 2 (L2)** retain their original interest rates, even if the global rate decreases.

---

## **Contracts Overview**

### **Core Contracts**

#### **RebaseToken.sol**
- ERC20-compatible rebase token.
- Handles user-specific interest accrual.
- Implements `mint` and `burn` functions restricted to vaults and pools.

#### **Vault.sol**
- Accepts ETH deposits and mints Rebase Tokens.
- Allows users to redeem ETH by burning tokens.
- Can be used to store protocol rewards.

#### **RebaseTokenPool.sol**
- Extends `TokenPool` (from Chainlink CCIP).
- Handles **lock-and-mint logic** across chains.
- Encodes user interest rate data in CCIP messages.

---

### **Scripts**

#### **BridgeTokenScript.sol**
- Executes token bridging using **CCIP**.
- Automates **approvals** and **fee estimation**.

#### **TokenAndPoolDeployer.sol**
- Deploys the Rebase Token and its pool on each chain.
- Registers the token in the **Chainlink Token Admin Registry**.

#### **VaultDeployer.sol**
- Deploys the vault on the **source chain only**.

---

## **Architecture**

```
User <-> Vault <-> RebaseToken
                  |
                  v
           RebaseTokenPool <-> Chainlink CCIP <-> Other Chains
```

#### **Deposit Flow**
```
ETH → Vault → Mints RBT (Rebase Tokens with user-specific rate).
```

#### **Bridge Flow**
```
User sends RBT → RebaseTokenPool → Burns on source chain → CCIP → Mints on destination chain with same interest rate.
```


## **Deployment**

#### **Deploy RebaseToken and Pool**
```
forge script script/TokenAndPoolDeployer.s.sol:TokenAndPoolDeployer \
    --broadcast \
    --rpc-url <SOURCE_RPC>
```

#### **Deploy RebaseToken and Pool**
```
forge script script/VaultDeployer.s.sol:VaultDeployer \
    --broadcast \
    --rpc-url <SOURCE_RPC> \
    --constructor-args <RebaseTokenAddress>
```

#### **Bridge Tokens**
```
forge script script/BridgeTokenScript.s.sol:BridgeTokenScript \
    --broadcast \
    --rpc-url <SOURCE_RPC> \
    --sig "run(address,uint64,address,address,uint256,address)" \
    <router> <destChainSelector> <receiver> <token> <amount> <linkToken>
```