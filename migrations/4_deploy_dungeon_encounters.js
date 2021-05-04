require("dotenv").config()
const DungeonEncounters = artifacts.require("DungeonEncounters")

const { VORCOORDINATOR_ADDRESS, XFUND_ADDRESS } = process.env

module.exports = function(deployer) {
  deployer.deploy(DungeonEncounters, VORCOORDINATOR_ADDRESS, XFUND_ADDRESS, "10000000", "10000000")
}
