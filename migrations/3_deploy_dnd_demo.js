require("dotenv").config()
const DnD = artifacts.require("DnD")

const { VORCOORDINATOR_ADDRESS, XFUND_ADDRESS } = process.env

module.exports = function(deployer) {
  deployer.deploy(DnD, VORCOORDINATOR_ADDRESS, XFUND_ADDRESS)
}
