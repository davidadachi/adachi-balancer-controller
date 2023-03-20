/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * https://trufflesuite.com/docs/truffle/reference/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */
require('dotenv').config();

const HDWalletProvider = require('@truffle/hdwallet-provider');
const newKitFromWeb3 = require('@celo/contractkit')
const Web3 = require('web3')

//const web3 = new Web3("https://alfajores-forno.celo-testnet.org");
//const web3_alfajores = new Web3(process.env.ALFAJORES_REST_URL);
const web3_celo = new Web3(process.env.CELO_REST_URL);
const kit = newKitFromWeb3.newKitFromWeb3(web3_celo) // Change to Celo web3 for main net deployment

const mnemonicPhrase = process.env.MNEMONIC;
const privateKey = process.env.PRIVATEKEY;

const account = web3_celo.eth.accounts.privateKeyToAccount(privateKey)
kit.connection.addAccount(account.privateKey);

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    // Useful for testing. The `development` name is special - truffle uses it by default
    // if it's defined here and no other network is specified at the command line.
    // You should run a client (like ganache, geth, or parity) in a separate terminal
    // tab if you use this network and you must also set the `host`, `port` and `network_id`
    // options below to some value.
    //
    development: {
     host: "127.0.0.1",     // Localhost (default: none)
     port: 7545,            // Standard Ethereum port (default: none)
     network_id: "*",       // Any network (default: none)
    },
    
    goerli: {
      provider: () => new HDWalletProvider(mnemonic, `https://goerli.infura.io/v3/${infuraProjectId}`),
      network_id: 5,       // Goerli's id
      chain_id: 5
    },
    xdai: {
      provider: () =>
      new HDWalletProvider({
        mnemonic: {
          phrase: mnemonicPhrase
        },
        providerOrUrl: "https://dai.poa.network",
      }),
      gas: 5000000,
      gasPrice: 10000000000,
      network_id: 100,
      networkCheckTimeout: 1000000000,
      confirmations: 5,
      timeoutBlocks: 900
    },
    celo: {
      provider: kit.connection.web3.currentProvider, // CeloProvider
      network_id: 42220                              // Alfajores Celo test netowrk network id
    }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.17",      // Fetch exact version from solc-bin
      settings: { // See the solidity docs for advice about optimization and evmVersion
        "viaIR": true,
        optimizer: {
            enabled: true,
            runs: 200,
        },
    },
    }
  }
};
