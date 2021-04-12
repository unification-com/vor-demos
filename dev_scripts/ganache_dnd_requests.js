require("dotenv").config()
const DnD = artifacts.require("DnD")

const { XFUND_ADDRESS, XFUND_ABI, VORCOORDINATOR_ADDRESS, VORCOORDINATOR_ABI, KEY_HASH } = process.env

function sleep (ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

module.exports = async function(callback) {
  const newtworkType = await web3.eth.net.getNetworkType();
  if(newtworkType !== "private") {
    console.log("run with Ganache")
    process.exit(1)
  }

  const numRollers = 10
  const dnd = await DnD.deployed()
  const accounts = await web3.eth.getAccounts()
  const xfund = await new web3.eth.Contract(JSON.parse(XFUND_ABI), XFUND_ADDRESS)
  const vorCoord = await new web3.eth.Contract(JSON.parse(VORCOORDINATOR_ABI), VORCOORDINATOR_ADDRESS)
  const consumerOwner = accounts[0]
  const provider = accounts[1]

  console.log("consumerOwner", consumerOwner)
  console.log("provider", provider)
  console.log("keyHash", KEY_HASH)
  console.log("dnd", dnd.address)

  const monster = await dnd.monsters(1)
  if(monster.ac.toNumber() === 0) {
    console.log("add monster")
    await dnd.addMonster( "orc", 16, { from: consumerOwner } )
  } else {
    console.log("using monster", monster.name, "AC", monster.ac.toNumber())
  }

  await dnd.increaseVorAllowance( "100000000000000000000000000", { from: consumerOwner } )
  let fromBlock = 0

  for(let i = 1; i < numRollers; i += 1) {
    const seed = Date.now()
    console.log("roll", i, "seed", seed)
    const acc = i + 1
    await xfund.methods.transfer(accounts[acc], 10).send({from: consumerOwner})
    await xfund.methods.increaseAllowance(dnd.address, 1).send({from: accounts[acc]})
    if(i > 0 && i <= 5) {
      await dnd.changeStrModifier(i, {from: accounts[acc]})
    }
    const tx = await dnd.rollForHit(1, seed, KEY_HASH, 1, {from: accounts[acc]})
    if(i === 0) {
      fromBlock = tx.receipt.blockNumber
    }
    await sleep(100)
  }

  console.log("wait....")

  await sleep(16000)

  const evs = await dnd.getPastEvents("HitResult", {fromBlock: fromBlock, toBlock: "latest"})

  for(let i = 0; i < evs.length; i += 1) {
    console.log(
      "HitResult Event - monster #",
      evs[i].returnValues.monsterId,
      "player",
      evs[i].returnValues.player,
      evs[i].returnValues.result,
      "roll",
      evs[i].returnValues.roll,
      "modified",
      evs[i].returnValues.modified)
  }

  for(let i = 1; i < numRollers; i += 1) {
    const acc = i + 1
    const res = await dnd.getLastResult(accounts[acc], 1)
    console.log(res)
  }

  callback()
}
