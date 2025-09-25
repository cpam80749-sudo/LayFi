# LayFi 🗂️
**Tokenized Layaway Plans – Save gradually for big purchases**

LayFi is a decentralized layaway system built on Stacks that allows users to create structured payment plans for large purchases. By tokenizing layaway plans, users can save gradually toward their goals while maintaining transparency and security through smart contracts.

## Overview

LayFi revolutionizes the traditional layaway model by bringing it to the blockchain, offering:

- **Tokenized Plans**: Each layaway plan is represented as a unique token
- **Flexible Payments**: Users can make payments at their own pace within plan parameters
- **Transparent Progress**: All payment history and plan status is recorded on-chain
- **Secure Escrow**: Funds are held securely in smart contracts until plan completion
- **Merchant Integration**: Businesses can easily integrate LayFi for customer payment plans

## Key Features

### For Customers
- Create personalized layaway plans with custom payment schedules
- Track progress through tokenized plan ownership
- Make payments incrementally toward purchase goals
- Withdraw completed plans to claim purchased items
- Cancel plans early with appropriate fee structures

### For Merchants
- Offer layaway options to increase customer accessibility
- Automatic payment tracking and verification
- Reduced payment processing overhead
- Integration with existing e-commerce systems

## Smart Contract Architecture

LayFi consists of two main smart contracts:

1. **`layaway-plans.clar`** - Core layaway plan management
   - Plan creation and lifecycle management
   - Payment processing and tracking
   - Plan completion and withdrawal logic
   - Fee calculation and distribution

2. **`plan-tokens.clar`** - Tokenization and ownership
   - NFT-like tokens representing layaway plans
   - Transfer and ownership management
   - Metadata and plan information storage
   - Token-based access control

## How It Works

1. **Plan Creation**: Users create a layaway plan specifying:
   - Target purchase amount
   - Payment schedule (weekly, bi-weekly, monthly)
   - Plan duration
   - Merchant/seller information

2. **Token Minting**: A unique plan token is minted to represent ownership

3. **Payment Processing**: Users make payments toward their plan:
   - Payments are tracked and verified on-chain
   - Progress updates automatically
   - Excess payments are handled appropriately

4. **Plan Completion**: Once fully paid:
   - Plan status changes to "completed"
   - Funds become available for merchant withdrawal
   - Customer receives completion certificate

5. **Withdrawal**: Merchants can withdraw funds for completed plans

## Technical Specifications

- **Blockchain**: Stacks
- **Smart Contract Language**: Clarity
- **Token Standard**: SIP-009 (NFT-like for plan tokens)
- **Testing Framework**: Clarinet + Vitest

## Getting Started

### Prerequisites
- Clarinet installed
- Node.js and npm
- Stacks wallet for testing

### Installation
```bash
git clone <repository-url>
cd LayFi
npm install
```

### Testing
```bash
# Check contract syntax
clarinet check

# Run tests
npm test
```

### Deployment
```bash
# Deploy to testnet
clarinet deploy --testnet

# Deploy to mainnet
clarinet deploy --mainnet
```

## Usage Examples

### Creating a Layaway Plan
```clarity
;; Create a 6-month plan for $1000 purchase with weekly payments
(contract-call? .layaway-plans create-plan 
    u1000000000 ;; 1000 STX in microSTX
    u26 ;; 26 weekly payments  
    u144 ;; 144 blocks per week
    "merchant-address")
```

### Making a Payment
```clarity
;; Make a $50 payment toward plan #1
(contract-call? .layaway-plans make-payment u1 u50000000)
```

### Checking Plan Status
```clarity
;; Get detailed plan information
(contract-call? .layaway-plans get-plan-details u1)
```

## Security Considerations

- All funds are held in escrow until plan completion
- Payment validation prevents overpayment exploitation
- Access controls ensure only plan owners can make payments
- Emergency functions allow for plan cancellation with appropriate penalties

## Contributing

We welcome contributions! Please see our contributing guidelines and submit pull requests for any improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions, issues, or support:
- Create an issue in this repository
- Join our community Discord
- Contact our development team

---

**LayFi** - Making big purchases accessible through decentralized layaway plans 🚀
