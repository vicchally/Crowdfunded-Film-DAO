# 🎬 Crowdfunded Film DAO

A decentralized autonomous organization for funding independent films through STX staking. Backers receive NFT credits, premiere invites, and streaming rights based on their contribution levels.

## 🚀 Features

- **🎯 Film Project Creation**: Filmmakers can create funding campaigns with goals and deadlines
- **💰 STX Staking**: Support films by staking STX tokens
- **🗳️ Community Voting**: Backers vote on funded films with weight based on their stake
- **🎁 Tiered Rewards**: Three reward levels based on contribution amounts
- **🎟️ Premiere Invites**: Exclusive access to film premieres for tier 2+ backers
- **📱 Streaming Rights**: Digital viewing access for all backers
- **🏆 NFT Credits**: Special NFT credits for top-tier supporters

## 📋 Contract Overview

The smart contract implements a complete crowdfunding system with the following core components:

- Film project management with funding goals and deadlines
- Tiered reward system (Tier 1: 500K+ STX, Tier 2: 500K+ STX, Tier 3: 1M+ STX)
- Voting mechanism for funded projects
- Reward distribution and claiming system

## 🛠️ Getting Started

### Prerequisites

- [Clarinet CLI](https://docs.hiro.so/stacks/clarinet)
- [Node.js](https://nodejs.org/) (for testing)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/Crowdfunded-Film-DAO.git
cd Crowdfunded-Film-DAO
```

2. Install dependencies:
```bash
npm install
```

3. Check contract syntax:
```bash
clarinet check
```

## 📖 Usage Guide

### For Filmmakers 🎬

#### 1. Create a Film Project
```clarity
(contract-call? .Crowdfunded-film-DAO create-film 
  "My Indie Film" 
  "A compelling story about..." 
  u10000000  ; 10 STX funding goal
  u30)       ; 30 days deadline
```

#### 2. Withdraw Funds (after successful funding)
```clarity
(contract-call? .Crowdfunded-film-DAO withdraw-funds u0) ; film-id 0
```

#### 3. Distribute Rewards (after voting period)
```clarity
(contract-call? .Crowdfunded-film-DAO distribute-rewards u0)
```

### For Backers 💰

#### 1. Fund a Film
```clarity
(contract-call? .Crowdfunded-film-DAO fund-film 
  u0        ; film-id
  u1000000) ; 1 STX amount
```

#### 2. Vote on Funded Films
```clarity
(contract-call? .Crowdfunded-film-DAO vote-on-film u0)
```

#### 3. Claim Rewards

**Streaming Rights (Tier 1+):**
```clarity
(contract-call? .Crowdfunded-film-DAO claim-streaming-rights u0)
```

**Premiere Invite (Tier 2+):**
```clarity
(contract-call? .Crowdfunded-film-DAO claim-premiere-invite u0)
```

**NFT Credits (Tier 3+):**
```clarity
(contract-call? .Crowdfunded-film-DAO claim-nft-credits u0)
```

## 🎯 Reward Tiers

| Tier | Minimum Stake | Rewards |
|------|---------------|---------|
| 🥉 **Tier 1** | 100K+ STX | Streaming Rights |
| 🥈 **Tier 2** | 500K+ STX | Streaming Rights + Premiere Invite |
| 🥇 **Tier 3** | 1M+ STX | All Rewards + NFT Credits |

## 🔍 Read-Only Functions

### Get Film Details
```clarity
(contract-call? .Crowdfunded-film-DAO get-film-details u0)
```

### Check Backer Information
```clarity
(contract-call? .Crowdfunded-film-DAO get-backer-info u0 'SP1234...)
```

### View Funding Progress
```clarity
(contract-call? .Crowdfunded-film-DAO get-funding-progress u0)
```

### Check Voting Information
```clarity
(contract-call? .Crowdfunded-film-DAO get-voting-info u0)
```

## 🔒 Security Features

- **Access Control**: Only film creators can withdraw funds and distribute rewards
- **Deadline Enforcement**: Funding and voting have strict time limits
- **Duplicate Prevention**: Users cannot vote multiple times on the same film
- **Tier Verification**: Reward claims are validated against contribution tiers

## 🧪 Testing

Run the test suite:
```bash
npm test
```

Run specific tests:
```bash
npm test -- --grep "funding"
```

## 📝 Contract Functions

### Public Functions
- `create-film` - Create a new film funding campaign
- `fund-film` - Contribute STX to a film project
- `vote-on-film` - Vote on a funded film (backers only)
- `distribute-rewards` - Enable reward claiming (creators only)
- `claim-premiere-invite` - Claim premiere access (Tier 2+)
- `claim-streaming-rights` - Claim streaming access (Tier 1+)
- `claim-nft-credits` - Claim NFT credits (Tier 3+)
- `withdraw-funds` - Withdraw raised funds (creators only)

### Read-Only Functions
- `get-film-details` - Film project information
- `get-backer-info` - Backer contribution details
- `get-voting-info` - Voting statistics
- `get-funding-progress` - Funding status and progress
- `get-reward-claim` - Reward claim information
- `is-film-deadline-passed` - Check if funding deadline passed

## 📊 Data Structures

### Film Project
```clarity
{
  creator: principal,
  title: string-ascii 64,
  description: string-ascii 256,
  funding-goal: uint,
  funding-raised: uint,
  deadline: uint,
  is-funded: bool,
  reward-distribution: bool
}
```

### Backer Information
```clarity
{
  amount: uint,
  reward-tier: uint
}
```

### Reward Claim
```clarity
{
  film-id: uint,
  recipient: principal,
  reward-type: string-ascii 32,
  claimed: bool,
  metadata: string-ascii 128
}
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://docs.hiro.so/stacks/clarinet)

## 💡 Future Enhancements

- 🎨 NFT marketplace integration
- 📺 Decentralized streaming platform
- 🏪 Film merchandise sales
- 📈 Revenue sharing mechanisms
- 🌐 Cross-chain compatibility
