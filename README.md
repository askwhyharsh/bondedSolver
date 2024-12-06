## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**
// bonded solver has vaults onchain where users can deposit funds, swap using rfq on cowswap
//  1. vaults — create vault, vault is created between a token pair and a yield bearing token or an nft is issued against it
//  1. swap — function to swap 2 tokens based on signed price sent by the solver
//  2. fee collector — fee from swaps are stored here

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
