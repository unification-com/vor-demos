# VOR Demos

This repo contains a selection of demo smart contracts which implement VOR

1. NFT Demo - live on Rinkeby [0xE1426CE899537340E5551cF37Db813B75Ec6C579](https://rinkeby.etherscan.io/address/0xE1426CE899537340E5551cF37Db813B75Ec6C579#code)
2. DnD Demo - live on Rinkeby [0x79C288Eccc6319563811B4Ca0A1F9D28b561Daf4](https://rinkeby.etherscan.io/address/0x79C288Eccc6319563811B4Ca0A1F9D28b561Daf4#code)
3. DungeonEncounters Demo - live on Rinkeby [0x1fcca2666cEb8fd9d2c9c4612f649a0F4DC80F00](https://rinkeby.etherscan.io/address/0x1fcca2666cEb8fd9d2c9c4612f649a0F4DC80F00#code)

## 1. Installing and deploying NFT Demo

1. `git clone https://github.com/unification-com/vor-demos`
2. `cd vor-demos`
3. `yarn install`
4. `cp example.env .env`
5. Edit `.env`. Respective contract addresses can be found [here](https://vor.unification.io/contracts.html)
6. `npx truffle compile`
7. `npx truffle migrate --reset --network=rinkeby`
8. Optionally `npx truffle run verify NFTCompetition --network=rinkeby`

### Simulations

The simulations require both Ganache and a VOR Oracle to be running, and 
the `xfund-vor` contracts to be deployed prior to running.

```bash
npx truffle deploy --network=develop
npx truffle exec simulations/ganache_nft_request.js --network=develop
npx truffle exec simulations/ganache_dnd_requests.js --network=develop
npx truffle exec simulations/ganache_dungeon_encounters_requests.js --network=develop
```
