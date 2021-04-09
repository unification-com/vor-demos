require("dotenv").config()
const NFTCompetition = artifacts.require("NFTCompetition")

const { XFUND_ADDRESS, XFUND_ABI } = process.env

function sleep (ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

module.exports = async function(callback) {
  const newtworkType = await web3.eth.net.getNetworkType();
  if(newtworkType !== "private") {
    console.log("run with Ganache")
    process.exit(1)
  }

  const nft = await NFTCompetition.deployed()
  const accounts = await web3.eth.getAccounts()
  const xfund = await new web3.eth.Contract(JSON.parse(XFUND_ABI), XFUND_ADDRESS)
  const consumerOwner = accounts[0]
  const maxEntries = 10

  console.log("consumerOwner", consumerOwner)
  console.log("nft", nft.address)

  for(let i = 1; i < maxEntries; i += 1) {
    const acc = i + 1
    await xfund.methods.transfer(accounts[acc], 1000).send({from: consumerOwner})
    await xfund.methods.increaseAllowance(nft.address, 1000).send({from: accounts[acc]})
  }

  await xfund.methods.increaseAllowance(nft.address, 1000).send({from: consumerOwner})
  await nft.increaseVorAllowance("100000000000000000000000000", {from: consumerOwner})

  const newComp = await nft.newCompetition("some_cool_nft", maxEntries, 1, {from: consumerOwner})
  const competitionId = newComp.logs[1].args.Id

  let c = await nft.getCompetition(competitionId)

  console.log(c)

  for(let i = 1; i < maxEntries; i += 1) {
    const acc = i + 1
    await nft.enterCompetition( competitionId, { from: accounts[acc] } )
  }

  c = await nft.getCompetition(competitionId)
  console.log(c)

  const receipt = await nft.runCompetition(12345, competitionId, {from: consumerOwner})

  console.log(receipt)

  console.log("wait....")

  await sleep(15000)

  const nftb1 = await nft.ownerOf(1)

  console.log("winner comp id", competitionId.toString(), "=", nftb1)

  callback()
}
