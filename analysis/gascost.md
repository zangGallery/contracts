# Polygon

## Stats
* Matic price (Feb 17): 1.74 USD
* Average gas price (Feb 16): 91 GWei
* Gas price (USD): 1.5834e-7

ZangNFT contract address: 0x277be76e409a737e013b16ffc5feaa369a7c078d

## Basic estimates
* Deployment: 3_523_631 gas (0.56 USD)
* Basic mint: 208_470 gas (0.03 USD)
* Subsequent mints: 191_370 gas (0.03 USD)

## NFT length vs gas 
* 0-length NFT: 236_680 gas (0.04 USD)
* 200-length NFT: 439_843 (0.07 USD)
* 500-length NFT: 731_985 (0.12 USD)

Linear interpolation: 236_780 + 990.41 * length, aka 0.04 + 0.00016 * length USD

# Optimism

## Stats
* ETH price (Feb 17): 2998 USD
* L1 gas price: 43 Gwei
* L1 gas price (USD): 1.3e-4
* L2 gas price: 0.001 Gwei
* L2 gas price (USD): 3e-9
* L1 fee scalar: 1.5

## Price computation in Optimism

Price = (L2 gas * L2 price) + (L1 gas * L1 price * L1 fee scalar)

## Basic estimates

ZangNFT contract address: 0x277be76e409a737e013b16ffc5feaa369a7c078d
Deployment: 3_523_631 L2 gas, 261_006 L1 gas (50.91 USD)

## NFT Length vs gas
* 0-length NFT: 253_780 L2 gas, 7_634 L1 gas (1.49 USD)
* 200-length NFT: 440_543 L2 gas, 11_886 L1 gas (2.32 USD)
* 500-length NFT: 735_285 L2 gas, 18_338 L1 gas (3.58 USD)

Linear interpolation (in USD): 1.49 + 0.00418 * length

# Arbitrum

## Stats

ETH price (Feb 17): 2998 USD
Gas price (Feb 17): 0.9 Gwei
Gas price (USD): 2.6982e-6

## Basic estimates

ZangNFT contract addess: 0x277be76e409a737e013b16ffc5feaa369a7c078d
Deployment: 54,260,427 gas (146.41 USD)

## NFT length vs gas
* 0-length NFT: 1_281_703 gas (3.46 USD)
* 200-length NFT: 2,171,485 gas (5.86 USD)
* 500-length NFT: 3_566_199 gas (9.62 USD)

Linear interpolation: 1_281_703 + 4_568.99 * length, aka 3.46 + 0.012 * length USD