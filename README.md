# VOR Demos

This repo contains a selection of demo smart contracts which implement VOR

1. NFT Demo - live on Rinkeby [0x4DA0AA5E015Ac4046907BfdA2D3a3dA8AD7D76Da](https://rinkeby.etherscan.io/address/0x4da0aa5e015ac4046907bfda2d3a3da8ad7d76da#code)

## 1. Installing and deploying NFT Demo

1. `git clone https://github.com/unification-com/vor-demos`
2. `cd vor-demos`
3. `yarn install`
4. `cp example.env .env`
5. Edit `.env`. Respective contract addresses can be found [here](https://vor.unification.io/contracts.html)
6. `npx truffle migrate --reset --network=rinkeby`
7. Optionally `npx truffle run verify NFTCompetition --network=rinkeby`
