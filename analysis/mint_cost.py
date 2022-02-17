# Script to run minting cost analysis

import base64
import os
from pathlib import Path

PRIVATE_KEY = 'YOUR_PRIVATE_KEY'
CONTRACT_ADDRESS = '0x277be76e409a737e013b16ffc5feaa369a7c078d'
ROYALTY_RECIPIENT = '0x0000000000000000000000000000000000000000'

RPC_URLS = {
    'polygon' : 'https://polygon-mumbai.g.alchemy.com/v2/YOUR_POLYGON_ALCHEMY_API_KEY',
    'arbitrum' : 'https://arb-rinkeby.g.alchemy.com/v2/YOUR_ARBITRUM_ALCHEMY_API_KEY',
    'optimism' : 'https://opt-kovan.g.alchemy.com/v2/YOUR_OPTIMISM_ALCHEMY_API_KEY'
}

EXTRA_ARGS = {
    'polygon' : '',
    'arbitrum' : '--legacy',
    'optimism' : '--legacy'
}
NFTS = {
    'fifth' : {
        'name' : 'The Fifth Amendment',
        'description' : 'Dec 15, 1791',
        'textURI' : 'data:text/markdown,The%20Fifth%20Amendment%0A----------%0A%0ANo%20person%20shall%20be%20held%20to%20answer%20for%20a%20capital%2C%20or%20otherwise%20infamous%20crime%2C%20unless%20on%20a%20presentment%20or%20indictment%20of%20a%20Grand%20Jury%2C%20except%20in%20cases%20arising%20in%20the%20land%20or%20naval%20forces%2C%20or%20in%20the%20Militia%2C%20when%20in%20actual%20service%20in%20time%20of%20War%20or%20public%20danger%3B%20nor%20shall%20any%20person%20be%20subject%20for%20the%20same%20offence%20to%20be%20twice%20put%20in%20jeopardy%20of%20life%20or%20limb%3B%20nor%20shall%20be%20compelled%20in%20any%20criminal%20case%20to%20be%20a%20witness%20against%20himself%2C%20nor%20be%20deprived%20of%20life%2C%20liberty%2C%20or%20property%2C%20without%20due%20process%20of%20law%3B%20nor%20shall%20private%20property%20be%20taken%20for%20public%20use%2C%20without%20just%20compensation+'
    }
}

def mint(address, chain, textURI, name, description, amount, royaltyNumerator, royaltyRecipient, length):
    rpc_url = RPC_URLS[chain]
    path = Path(os.path.realpath(__file__)).parent / 'results' / chain / f'mint-{name.replace(" ", "")}-{length}.txt'
    path.parent.mkdir(parents=True, exist_ok=True)

    extra_args = EXTRA_ARGS[chain]

    command = (f'cast send --private-key {PRIVATE_KEY} {address} "mint(string memory, string memory, string memory, uint256, uint96, address, bytes memory)(uint256)" "{textURI}" "{name}" "{description}" {amount} {royaltyNumerator} {royaltyRecipient} "" {extra_args} --rpc-url {rpc_url} >> {path}')
    print(command)
    os.system(command)

def main():

    name = 'Standard Name'
    description = 'My somewhat standard-length description'

    for chain in ['polygon', 'arbitrum', 'optimism']:
        print(f'Chain "{chain}')
        for i, length in enumerate([0, 200, 500]):
            print(f'Test #{i+1}')

            text = 'a' * length
            textURI = 'data:text/markdown,' + base64.b64encode(text.encode('ascii')).decode('ascii')

            mint(CONTRACT_ADDRESS, chain, textURI, name, description, 10, 100, ROYALTY_RECIPIENT, length)

if __name__ == '__main__':
    main()