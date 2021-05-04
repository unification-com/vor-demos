require("dotenv").config()
const DungeonEncounters = artifacts.require("DungeonEncounters")

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

  const numSims = 20
  const numPlayers = 15
  const highestMonsterDefeated = {}
  const wonLastEncounter = {}
  const healingPotionsDrunk = {}
  const simStats = {
    numRolls: 0,
    rollData: {}
  }
  const encounters = await DungeonEncounters.deployed()
  const accounts = await web3.eth.getAccounts()
  const xfund = await new web3.eth.Contract(JSON.parse(XFUND_ABI), XFUND_ADDRESS)
  const vorCoord = await new web3.eth.Contract(JSON.parse(VORCOORDINATOR_ABI), VORCOORDINATOR_ADDRESS)
  const consumerOwner = accounts[0]
  const provider = accounts[1]

  const fee = await vorCoord.methods.getProviderGranularFee(KEY_HASH, encounters.address).call()
  const statFee = await encounters.statFee()
  const healingPotionFee = await encounters.healingPotionFee()
  const maxHealingPotions = await encounters.maxHealingPotions()

  console.log("consumerOwner", consumerOwner)
  console.log("provider", provider)
  console.log("keyHash", KEY_HASH)
  console.log("encounters", encounters.address)
  console.log("fee", fee.toString())

  const monster = await encounters.monsters(1)
  if(monster.ac.toNumber() === 0) {
    console.log("add monsters")
    await encounters.addMonster( "goblin", 12, 12, 0, 4, 0, { from: consumerOwner } )
    await encounters.addMonster( "skeleton", 14, 15, 1, 4, 1, { from: consumerOwner } )
    await encounters.addMonster( "orc", 15, 17, 1, 6, 1, { from: consumerOwner } )
    await encounters.addMonster( "troll", 17, 25, 2, 8, 2, { from: consumerOwner } )
    await encounters.addMonster( "mind flayer", 18, 45, 3, 10, 3, { from: consumerOwner } )
    await encounters.addMonster( "beholder", 19, 50, 4, 10, 4, { from: consumerOwner } )
    await encounters.addMonster( "lich", 23, 80, 6, 10, 8, { from: consumerOwner } )
    await encounters.addMonster( "demi god", 25, 100, 10, 12, 10, { from: consumerOwner } )
    await encounters.addMonster( "deity", 30, 150, 12, 12, 12, { from: consumerOwner } )
  }

  const nextMonsterId = await encounters.nextMonsterId()
  const highestMonsterId = nextMonsterId.toNumber() - 1

  await encounters.increaseVorAllowance( "100000000000000000000000000", { from: consumerOwner } )

  for(let i = 1; i <= numPlayers; i += 1) {
    const acc = i + 1
    const p = await encounters.players(accounts[acc])
    if(p.hp.toNumber() === 0 ) {
      await encounters.createPlayer(`p_${i}`, {from: accounts[acc]})
    }
    highestMonsterDefeated[accounts[acc]] = 0
  }

  for(let s = 1; s <= numSims; s += 1) {
    console.log("Simulation", s)
    for ( let i = 1; i <= numPlayers; i += 1 ) {
      const acc = i + 1
      let player = await encounters.players(accounts[acc])

      if(!wonLastEncounter[accounts[acc]] && s > 1) {
        console.log( "Increase player stats" )

        const maxPlayerAc = await encounters.maxPlayerAc()
        const maxPlayerHp = await encounters.maxPlayerHp()
        const maxPlayerStr = await encounters.maxPlayerStr()
        const maxPlayerAtk = await encounters.maxPlayerAtk()
        const maxPlayerDmg = await encounters.maxPlayerDmg()

        if ( player.ac.toNumber() < maxPlayerAc.toNumber()) {
          await xfund.methods.transfer( accounts[acc], statFee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, statFee ).send( { from: accounts[acc] } )
          await encounters.increaseArmourClass( { from: accounts[acc] } )
        }

        if ( player.hp.toNumber() < maxPlayerHp.toNumber() ) {
          await xfund.methods.transfer( accounts[acc], statFee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, statFee ).send( { from: accounts[acc] } )
          await encounters.increaseHitPoints( { from: accounts[acc] } )
        }

        if ( player.str.toNumber() < maxPlayerStr.toNumber() ) {
          await xfund.methods.transfer( accounts[acc], statFee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, statFee ).send( { from: accounts[acc] } )
          await encounters.increaseStrengthModifier( { from: accounts[acc] } )
        }

        if ( player.atk.toNumber() < maxPlayerAtk.toNumber() ) {
          await xfund.methods.transfer( accounts[acc], statFee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, statFee ).send( { from: accounts[acc] } )
          await encounters.increaseAttackDice( { from: accounts[acc] } )
        }

        if ( player.dmg.toNumber() < maxPlayerDmg.toNumber() ) {
          await xfund.methods.transfer( accounts[acc], statFee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, statFee ).send( { from: accounts[acc] } )
          await encounters.increaseDamageModifier( { from: accounts[acc] } )
        }
      }

      let monsterId = highestMonsterDefeated[accounts[acc]] + 1
      if(monsterId > highestMonsterId) {
        monsterId = highestMonsterId
      }

      const encounterMonster = await encounters.monsters(monsterId)

      console.log("create new  encounter")
      const tx = await encounters.newEncounter( monsterId, { from: accounts[acc] } )

      const encounterId = tx.logs[0].args.encounterId
      const watchFrom = tx.receipt.blockNumber

      console.log( "Running encounterId", encounterId )
      console.log("monster:", encounterMonster.name)
      console.log("AC:", encounterMonster.ac.toNumber())
      console.log("HP:", encounterMonster.hp.toNumber())
      console.log("STR:", encounterMonster.str.toNumber())
      console.log("ATK:", encounterMonster.atk.toNumber())
      console.log("DMG:", encounterMonster.dmg.toNumber())

      player = await encounters.players(accounts[acc])
      console.log("player:", player.name)
      console.log("AC:", player.ac.toNumber())
      console.log("HP:", player.hp.toNumber())
      console.log("STR:", player.str.toNumber())
      console.log("ATK:", player.atk.toNumber())
      console.log("DMG:", player.dmg.toNumber())

      let encounter = await encounters.encounters( encounterId )
      let rollCounter = 1;

      let encounterRunning = true

      const encounterStats = {
        rolls: 0,
        playerHits: 0,
        playerCrits: 0,
        playerMisses: 0,
        playerNat1: 0,
        monsterHits: 0,
        monsterCrits: 0,
        monsterMisses: 0,
        monsterNat1: 0,
      }
      while ( encounterRunning ) {
        if ( encounter.isRolling ) {
          process.stdout.write( "." )
        } else {
          const seed = Date.now()
          console.log( "" )
          console.log( "sim", `${s}/${numSims}`, "player", `${i}/${numPlayers}`, "request", `#${rollCounter}` )
          rollCounter += 1
          await xfund.methods.transfer( accounts[acc], fee ).send( { from: consumerOwner } )
          await xfund.methods.increaseAllowance( encounters.address, fee ).send( { from: accounts[acc] } )
          await encounters.beginCombatRound( encounterId, seed, KEY_HASH, fee, { from: accounts[acc] } )
        }

        await sleep( 50  )

        encounter = await encounters.encounters( encounterId )
        if ( encounter.monsterHp.toNumber() === 0 || encounter.playerHp.toNumber() === 0 ) {
          console.log( "" )
          console.log( "Encounter over" )
          encounterRunning = false
        } else {
          if ( encounter.playerHp.toNumber() <= 10 ) {
            player = await encounters.players( accounts[acc] )
            if ( player.healingPotions.toNumber() > 0 ) {
              console.log( "Drink healing potion" )
              await encounters.drinkHealingPotion( encounterId, { from: accounts[acc] } )
              healingPotionsDrunk[accounts[acc]] = (healingPotionsDrunk[accounts[acc]]) ? healingPotionsDrunk[accounts[acc]] + 1 : 1
            }
          }
        }
      }

      console.log( "Encounter results" )

      const pEvs = await encounters.getPastEvents( "PlayerResult", {
        filter: { encounterId: encounterId },
        fromBlock: watchFrom,
        toBlock: "latest"
      } )
      const mEvs = await encounters.getPastEvents( "MonsterResult", {
        filter: { encounterId: encounterId },
        fromBlock: watchFrom,
        toBlock: "latest"
      } )
      const encEvs = await encounters.getPastEvents( "EncounterOver", {
        filter: { encounterId: encounterId },
        fromBlock: watchFrom,
        toBlock: "latest"
      } )

      if ( pEvs.length > 0 ) {
        for ( let i = 0; i < pEvs.length; i += 1 ) {
          simStats.numRolls++
          console.log( "Roll number", i + 1 )
          console.log( "PlayerResult",
            "rolled", pEvs[i].returnValues.roll,
            "mod", pEvs[i].returnValues.modified,
            "hit", pEvs[i].returnValues.hit,
            "crit", pEvs[i].returnValues.isCrit,
            "dmg", pEvs[i].returnValues.damage,
            "monsterHp", pEvs[i].returnValues.monsterHp )

          if ( pEvs[i].returnValues.hit ) {
            encounterStats.playerHits++
          } else {
            encounterStats.playerMisses++
          }
          if ( pEvs[i].returnValues.isCrit ) {
            encounterStats.playerCrits++
          }
          if ( parseInt( pEvs[i].returnValues.roll, 10 ) === 1 ) {
            encounterStats.playerNat1++
          }
          encounterStats.rolls++

          simStats.rollData[pEvs[i].returnValues.roll] = (simStats.rollData[pEvs[i].returnValues.roll]) ? simStats.rollData[pEvs[i].returnValues.roll] + 1 : 1

          if ( mEvs[i] ) {

            // each roll request is split into 4 results (2 "hit" results & 2 dmg results) so count this too
            encounterStats.rolls++
            simStats.numRolls++

            console.log( "MonsterResult",
              "rolled", mEvs[i].returnValues.roll,
              "mod", mEvs[i].returnValues.modified,
              "hit", mEvs[i].returnValues.hit,
              "crit", mEvs[i].returnValues.isCrit,
              "dmg", mEvs[i].returnValues.damage,
              "playerHp", mEvs[i].returnValues.playerHp )

            if ( mEvs[i].returnValues.hit ) {
              encounterStats.monsterHits++
            } else {
              encounterStats.monsterMisses++
            }
            if ( mEvs[i].returnValues.isCrit ) {
              encounterStats.monsterCrits++
            }
            if ( parseInt( mEvs[i].returnValues.roll, 10 ) === 1 ) {
              encounterStats.monsterNat1++
            }
            simStats.rollData[pEvs[i].returnValues.roll] = (simStats.rollData[pEvs[i].returnValues.roll]) ? simStats.rollData[pEvs[i].returnValues.roll] + 1 : 1
          }
        }
      }

      console.log( encounterStats )

      if ( encEvs.length > 0 ) {
        const playerWon = encEvs[encEvs.length - 1].returnValues.playerWon
        wonLastEncounter[accounts[acc]] = playerWon
        console.log( "Winner:", ( playerWon ) ? "Player" : "Monster" )
        if(playerWon) {
          highestMonsterDefeated[accounts[acc]] = monsterId
        } else {
          player = await encounters.players(accounts[acc])
          if(player.healingPotions < maxHealingPotions) {
            console.log( "Buy healing potion" )
            await xfund.methods.transfer( accounts[acc], healingPotionFee ).send( { from: consumerOwner } )
            await xfund.methods.increaseAllowance( encounters.address, healingPotionFee ).send( { from: accounts[acc] } )
            await encounters.buyHealingPotion( { from: accounts[acc] } )
          }
        }
      }
    }
  }

  console.log("d20 stats")
  console.log("total rolls", simStats.numRolls)
  for (const property in simStats.rollData) {
    const num = simStats.rollData[property]
    let perc = 0
    if(num > 0) {
      perc = (num).toFixed(2) / ( simStats.numRolls ).toFixed( 2 ) * 100
    }
    console.log(property, "=", simStats.rollData[property], `(${perc.toFixed(2)}%)`)

  }

  console.log("Player stats")
  for ( let i = 1; i <= numPlayers; i += 1 ) {
    const acc = i + 1
    const player = await encounters.players(accounts[acc])
    console.log(player.name)
    console.log("Won:", player.won.toNumber())
    console.log("Lost:", player.lost.toNumber())
    console.log("Healing Potions Consumed:", healingPotionsDrunk[accounts[acc]])
    const highestMonster = await encounters.monsters(highestMonsterDefeated[accounts[acc]])
    console.log("Highest Monster Defeated:", highestMonster.name)
  }

  callback()
}
