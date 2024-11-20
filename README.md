## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Install
```shell
yarn install
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2 --no-commit
forge install OpenZeppelin/openzeppelin-foundry-upgrades@v0.3.6 --no-commit
```


### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
#### test a specific contract
```shell
forge test --match-contract MinterTest -vvvvv --via-ir 
forge clean && forge test --match-contract MinterTest -vvvvv --via-ir
forge clean && forge test --match-contract BuybackTest -vvv --via-ir
forge clean && forge test --match-contract BuybackTest --match-test "testBuybackSuccess" -vvvv --via-ir
forge clean && forge test --match-contract BuybackTest --match-test "testBuybackFail" -vvvv --via-ir
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
$ forge script <path_to_script> --rpc-url <your_rpc_url> --private-key <your_private_key> --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv --via-ir
# deploy the proxy contract of Minter
$ forge script script/AsBnbMinter.s.sol:MinterScript --rpc-url <your_rpc_url> --private-key <your_private_key> --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv --via-ir
# deploy the implementation contract of Minter
$ forge script script/AsBnbMinterImpl.s.sol:MinterImplScript --rpc-url <your_rpc_url> --private-key <your_private_key> --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv --via-ir
# deploy the contract of MockERC20
$ forge script script/mock/MockERC20.s.sol:MockERC20Script --rpc-url <your_rpc_url> --private-key <your_private_key> --etherscan-api-key <bscscan-api-key> --broadcast --verify -vvv --via-ir

# deploy to local node
forge script script/mock/MockERC20.s.sol:MockERC20Script
```

### Cast

```shell
$ cast <subcommand>
$ cast call <contract_address> <method_name> <method_args>
$ cast send <contract_address> <method_name> <method_args> --private-key <private_key>
# demo
$ cast send <contract_address> "smartMint(uint256,uint16,uint256)" <...parameters> --rpc-url $RPC --private-key $PRIVATE_KEY 
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
