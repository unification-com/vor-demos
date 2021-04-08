require("dotenv").config()
const HDWalletProvider = require('@truffle/hdwallet-provider');

const {
  ETH_PKEY,
  INFURA_PROJECT_ID,
  ETHERSCAN_API,
} = process.env

module.exports = {
  networks: {
    // ganache-cli
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
    },
    // truffle develop console
    develop: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },
    rinkeby: {
      provider: () =>
        new HDWalletProvider({
          privateKeys: [ETH_PKEY],
          providerOrUrl: `https://rinkeby.infura.io/v3/${INFURA_PROJECT_ID}`
        }),
      network_id: "4",
      gas: 10000000,
      gasPrice: 100000000000,
      skipDryRun: true,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider({
          privateKeys: [ETH_PKEY],
          providerOrUrl: `https://mainnet.infura.io/v3/${INFURA_PROJECT_ID}`
        }),
      network_id: "1",
      gasPrice: 120000000000 // 120e9 = 120 gwei
    }
  },


  plugins: [
    'truffle-plugin-verify'
  ],

  api_keys: {
    etherscan: ETHERSCAN_API
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.6.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  }
};
