require("dotenv").config()
const NFTCompetition = artifacts.require("NFTCompetition")

const { KEY_HASH, VORCOORDINATOR_ADDRESS, VORCOORDINATOR_ABI, XFUND_ADDRESS, XFUND_ABI } = process.env

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
  const vorCoord = await new web3.eth.Contract(JSON.parse(VORCOORDINATOR_ABI), VORCOORDINATOR_ADDRESS)
  const consumerOwner = accounts[0]
  const provider = accounts[1]
  const maxEntries = 10

  const fee = await vorCoord.methods.getProviderGranularFee(KEY_HASH, nft.address).call()

  console.log("consumerOwner", consumerOwner)
  console.log("provider", provider)
  console.log("keyHash", KEY_HASH)
  console.log("nft", nft.address)
  console.log("fee", fee.toString())

  await nft.setRandomnessFee(fee.toString(), {from: consumerOwner})

  console.log("init accs")
  for(let i = 1; i < maxEntries; i += 1) {
    const acc = i + 1
    await xfund.methods.transfer(accounts[acc], 1000).send({from: consumerOwner})
    await xfund.methods.increaseAllowance(nft.address, 1000).send({from: accounts[acc]})
  }

  console.log("init nft contract")
  await xfund.methods.increaseAllowance(nft.address, fee.toString()).send({from: consumerOwner})
  await nft.increaseVorAllowance("100000000000000000000000000", {from: consumerOwner})

  console.log("create new competition")
  const newComp = await nft.newCompetition("some_cool_nft", maxEntries, 1, {from: consumerOwner})

  const competitionId = newComp.logs[2].args.Id

  for(let i = 1; i < maxEntries; i += 1) {
    const acc = i + 1
    console.log("acc", acc, "enter competition", competitionId.toString() )
    await nft.enterCompetition( competitionId, { from: accounts[acc] } )
  }

  const comp = await nft.getCompetition(competitionId)
  console.log("competition info", comp)

  const entries = await nft.getCompetitionEntries(competitionId)
  console.log("competition entries", entries)

  console.log("run competition", competitionId.toString())
  const runReceipt = await nft.runCompetition(12345, competitionId, {from: consumerOwner})

  console.log(runReceipt)

  console.log("wait....")

  await sleep(15000)

  const compResults = await nft.getCompetition(competitionId)
  console.log("competition results", compResults)

  console.log("winner comp id", competitionId.toString(), "=", compResults.winner)
  const nftOwnerBefore = await nft.ownerOf(competitionId)
  console.log("nft owner", nftOwnerBefore)

  console.log("claim prize")

  await nft.claimPrize(competitionId, {from: compResults.winner})

  const nftOwnerAfter = await nft.ownerOf(competitionId)
  console.log("new nft owner", nftOwnerAfter)

  callback()
}
