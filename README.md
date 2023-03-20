# balancer.controller

In traditional banking, the reserve ratio is the portion of reservable liabilities that commercial banks must hold onto, rather than lend out or invest, with this reserve usually being set by the nations central bank.
This minimum amount that a bank must hold is known as the reserve requirement (RR), sometimes used interchangeabily with the term reserve ratio.

The reason the reserve ratio requirement exists is to ensure sufficient liquidity (cash) exists in the bank to handle events such as a sudden run on bank withdrawals by customers but it can also be used as a part of monetary policy to expand or restrict liquidity in a system.

The researve ratio is defined as follows.

```bash
Reserve Requirement = Deposits × Reserve Ratio
```

This project provides a smart contract that allows a reserve ratio to be set and then by tracking deposits within Balancer managed pools, can detect when a reserve requirement is breached. When this happens, liquidity can be sent automatically to the managed pool to move it back inside its limit.


## Contracts

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

- [`Base.sol`](./conttracts): An abstract base smart contract that forms the basis of all controllers.

## Build and Test

Before any tests can be run, the repository needs to be prepared:

```bash
$ npm install # install all dependencies
```

Most tests are standalone and simply require installation of dependencies and compilation.

In order to run all tests (including those with extra dependencies), run:

```bash
$ truffle compile
$ truffle test
```

## Licensing

Most of the Solidity source code is licensed under the GNU General Public License Version 3 (GPL v3): see [`LICENSE`](./LICENSE).
