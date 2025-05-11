### DeFi Yield Optimizer

A smart contract that automatically allocates funds across different yield-generating protocols based on user risk profiles and current APY rates.

## Overview

This Yield Optimizer is a Clarity smart contract designed for the Stacks blockchain that helps users maximize their yield by automatically distributing their funds across different DeFi protocols. The contract takes into account the user's risk tolerance and the current APY of each protocol to determine the optimal allocation.

## Features

- **Risk-Based Allocation**: Users can set their risk profile (conservative, moderate, or aggressive) to influence how their funds are allocated
- **Multiple Strategy Support**: Contract can manage multiple yield-generating protocols simultaneously
- **Automatic Rebalancing**: Funds are automatically rebalanced when risk profiles change or when new deposits are made
- **Manual Allocation**: Users can manually specify their preferred allocation across strategies
- **Emergency Controls**: Contract includes pause functionality and token recovery for emergency situations


## How It Works

1. **Strategy Management**: The contract owner adds yield-generating protocols as strategies, each with an associated risk score and APY
2. **User Deposits**: Users deposit funds into the contract and set their risk profile
3. **Automatic Allocation**: The contract allocates the user's funds across strategies based on their risk profile
4. **Yield Generation**: Funds earn yield according to the APY of each strategy
5. **Withdrawals**: Users can withdraw their funds (including earned yield) at any time


## Contract Functions

### Admin Functions

- `set-asset-contract`: Set the main token contract used by the optimizer
- `add-strategy`: Add a new yield-generating protocol as a strategy
- `update-strategy-apy`: Update the APY of an existing strategy
- `set-strategy-active`: Enable or disable a strategy
- `set-paused`: Pause or unpause the contract
- `recover-tokens`: Emergency function to recover tokens from the contract


### User Functions

- `deposit`: Deposit funds into the optimizer
- `withdraw`: Withdraw funds from the optimizer
- `set-risk-profile`: Set your risk profile (conservative, moderate, or aggressive)
- `reallocate-funds`: Manually reallocate your funds across strategies


### Read-Only Functions

- `get-user-total-value`: Get the total value of a user's deposits
- `get-strategy`: Get details about a specific strategy
- `get-user-risk-profile`: Get a user's current risk profile
- `get-user-allocation`: Get a user's allocation for a specific strategy
- `get-total-funds-locked`: Get the total funds locked in the contract
- `get-strategy-count`: Get the total number of strategies
- `is-paused`: Check if the contract is paused


## Risk Profiles

The contract supports three risk profiles:

1. **Conservative (1)**: Prioritizes safety over returns, allocating more funds to lower-risk strategies
2. **Moderate (2)**: Balanced approach between risk and returns
3. **Aggressive (3)**: Prioritizes higher returns, allocating more funds to higher-risk strategies


## Technical Details

- **Allocation Units**: Allocations are specified in basis points (1/100 of a percent), with 10000 representing 100%
- **Token Standard**: The contract works with any token that implements the SIP-010 fungible token standard
- **Error Handling**: Comprehensive error codes for clear error identification


## Development and Testing

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet): A Clarity development tool
- [Stacks CLI](https://github.com/blockstack/stacks.js): Command-line interface for the Stacks blockchain


### Testing

The contract includes a comprehensive test suite using Vitest. To run the tests:

```shellscript
npm test
```

### Deployment

To deploy the contract to the Stacks blockchain:

1. Build the contract:


```shellscript
clarinet build
```

2. Deploy using the Stacks CLI:


```shellscript
stacks deploy --network mainnet stx-yield-navigator.clar
```

## Security Considerations

- The contract includes emergency pause functionality
- Owner-only functions are protected with access control
- Funds can be recovered in case of emergencies
- Input validation is performed for all user inputs


## Future Enhancements

- Integration with specific DeFi protocols
- More sophisticated allocation algorithms based on historical performance
- Yield harvesting and compounding
- Governance mechanisms for strategy management


## License

This project is licensed under the MIT License - see the LICENSE file for details.