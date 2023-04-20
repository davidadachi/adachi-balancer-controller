const ContractKit = require('@celo/contractkit');
const Web3 = require('web3');

require('dotenv').config({path: '.env'});

const HDWalletProvider = require('@truffle/hdwallet-provider');

const web3_alfajores = new Web3(process.env.ALFAJORES_REST_URL);
const web3_celo = new Web3(process.env.CELO_REST_URL);

// Initialise a Celo client
const client = ContractKit.newKitFromWeb3(web3_celo);

// Initialize account from our private key
const account = web3_celo.eth.accounts.privateKeyToAccount(process.env.PRIVATE_KEY);

// We need to add private key to ContractKit in order to sign transactions
client.addAccount(account.privateKey);

// Mnemonic phrase used with HDWallet
const mnemonicPhrase = process.env.MNEMONIC;

module.exports = {
  compilers: {
    solc: {
      version: "0.7.6",      // Fetch exact version from solc-bin
      settings: { // See the solidity docs for advice about optimization and evmVersion
    },
    }
  },
  networks: {
    test: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*"
    },
    alfajores: {
      provider: client.connection.web3.currentProvider, // CeloProvider
      network_id: 44787  // Alfajores network id
    },
    celo: {
      provider: client.connection.web3.currentProvider, // CeloProvider
      network_id: 42220  // Celo network id
    },
    gnosis: {
      provider: () =>
      new HDWalletProvider({
        mnemonic: {
          phrase: mnemonicPhrase
        },
        providerOrUrl: process.env.GNOSIS_REST_URL,
      }),
      gas: 5000000,
      gasPrice: 10000000000,
      network_id: 100,
      networkCheckTimeout: 1000000000,
      confirmations: 5,
      timeoutBlocks: 900
    },
    goerli: {
      provider: () => new HDWalletProvider(mnemonic, `${process.env.GOERLI_REST_URL}${infuraProjectId}`),
      network_id: 5,
      chain_id: 5
    },
  }
};