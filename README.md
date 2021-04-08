# VOR Demos

This repo contains a selection of demo smart contracts which implement VOR

1. NFT Demo - live on Rinkeby [0x5252ED67e0B140cb6b619304955cdbA795fbC013](https://rinkeby.etherscan.io/address/0x5252ED67e0B140cb6b619304955cdbA795fbC013#code)

## 1. Installing and deploying NFT Demo

1. `git clone https://github.com/unification-com/vor-demos`
2. `cd vor-demos`
3. `yarn install`
4. `cp example.env .env`
5. Edit `.env`. Respective contract addresses can be found [here](https://vor.unification.io/contracts.html)
6. `npx truffle compile`
7. `npx truffle migrate --reset --network=rinkeby`
8. Optionally `npx truffle run verify NFTCompetition --network=rinkeby`
