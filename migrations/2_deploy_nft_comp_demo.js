require("dotenv").config()
const NFTCompetition = artifacts.require("NFTCompetition")

const { VORCOORDINATOR_ADDRESS, XFUND_ADDRESS, KEY_HASH, RANDOMNESS_FEE, TOKEN_NAME, TOKEN_SYMBOL } = process.env

module.exports = function(deployer) {
  deployer.deploy(NFTCompetition, VORCOORDINATOR_ADDRESS, XFUND_ADDRESS, KEY_HASH, RANDOMNESS_FEE, TOKEN_NAME, TOKEN_SYMBOL)
}
