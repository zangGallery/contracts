# Attacks

## Glossary

- EOA: Externally Owned Account. An address that is not a contract address
- DAO: Decentralized Autonomous Organization. An organization involving a smart contract capable of executing
  transactions on behalf of its members. Usually involves some sort of voting mechanism
- zang's owner: the address registered on zang's marketplace contract as its owner. Could be an EOA or a contract address
- zang's commission account: the address registered on zang's marketplace contract as the beneficiary of commissions. Could
  be the same account as zang's owner or a different account
- EIP-2981: Ethereum Improvement Proposal 2981 (NFT Royalty Standard). Standardizes royalty mechanisms for
  NFTs

## Account Compromission

Description: An attack where a malicious entity gains access to an account and uses it to execute otherwise
restricted operations.

The most serious form of Account Compromission involves an attacker obtaining an account's private key, allowing
the attacker to fully impersonate the victim. A milder version of this attack involves using an exploit in a
contract to force the contract to execute some restricted actions (e.g. forcing a contract to sell an NFT).

There are three noteworthy accounts that should be considered:
- zang's owner
- zang's commission account
- Individual users

### Mitigation

The responsibility for securing an account falls on the account's owner; however, zang's contracts can mitigate
damages by limiting the power of all accounts to the bare minimum.

A noteworthy case involves a situation where zang's owner's account is compromised, but zang's commission account isn't (and
vice versa).
This situation can lead to a deadlock where no party is capable of stopping the other party, for better or worse.

However, the design of zang's contracts is such that a takeover of any of the two accounts leads to the same effects:
- zang's beneficiary of the commissions stops receiving revenue:
    - If the owner's account is compromised, the attacker can pause the marketplace contract
    - If the commission account is compromised, the attacker can redirect the revenue stream to unauthorized entities
- The attacker can block all sales on the platform
    - If the owner's account is compromised, the attacker can pause the marketplace contract
    - If the commission account is compromised, the attacker can launch a Platform Freeze attack (see Platform Freeze, zang variant)

Since both takeovers are equally bad, we can at least render one takeover ineffective by establishing a hierarchy between the two accounts.
This can be done by allowing the owner's account to change the address that receives commissions.

Doing so enables zang's owner to stop further revenue theft by the attacker.

## Platform Freeze

Description: An attack that involves blocking all sales on the platform for malicious purposes.

Note that there can be genuine reasons for blocking all sales, such as to prevent attackers from exploiting
a vulnerability in zang's marketplace contract.

Since zang's owner can pause all sales on the platform, an Account Compromission attack allows the attacker to
execute a Platform Freeze. However, there can be other ways to execute a Platform Freeze, such as through the
compromission of zang's commission account (see Sale Denial attack, zang variant).

### Mitigation

The main mitigation for this type of attack involves ensuring that a Platform Freeze has no adverse effects
on users beyond the impossibility to sell on the marketplace.
For example, users should still be able to:
- Mint NFTs
- Transfer NFTs
- List NFTs on a different marketplace

This can be achieved by separating the marketplace contract from the ZangNFT contract. Since zang's owner can
only pause the marketplace contract, in case of a Platform Freeze users would still be able to continue minting
(through the ZangNFT contract) and selling (through either an updated version of the marketplace contract or a
different marketplace altogether).

## Sale Denial

Description: An attack that prevents the successful execution of a specific sale.

During a sale on zang, money is transferred to three entities:
- zang's commission account
- The NFT's royalty recipient
- The seller

In order for a sale to be successful, all three money transfers must succeed.
This isn't an issue for EOAs (aka normal addresses). However, contract addresses can revert the
transfer transaction.
In other words, contracts can prevent a sale by refusing to accept Ether.

### zang

Since zang's owner is also the owner of the zang commission account, everything that can be achieved
by rejecting Ether can also be achieved by simply pausing the Marketplace contract. In other words, a
Platform Freeze attack allows the attacker to execute a Sale Denial attack.

The only interesting case is when the zang commission account gets compromised (e.g. private key leak)
but zang's owner's account doesn't. In such case, the attacker could block all sales, leading to a Platform
Freeze attack.

### Seller

Sellers can block the execution of a sale; however, doing so is equivalent to not selling in the first place.
The only feasible situation in which a seller might want to do so is in order to restrict who can purchase the
NFT.

For example, suppose that the seller A is a contract with a boolean flag `acceptMoney` that defaults to `false`.
An authorized address B could, within the same atomic transaction:
1. Bob calls Alice's contract
    1a. Alice's contract verifies that Bob has the rights to purchase the NFT
    1b. Alice's contract sets `acceptMoney` to `true`
2. Bob calls zang's buy function()
    2a. zang tries to transfer the Ether to Alice
    2b. Alice accepts
    2c. zang transfers the NFT to Bob
3. (In case of multiple listings) Bob calls Alice's contract again
    3a. Alice's contract sets `acceptMoney` to `false`

Note that this situation is equivalent to selling the NFT on a marketplace that restricts purchases to certain users.

### Royalty recipient

Similarly to the seller, the royalty recipient can block a sale by rejecting incoming Ether.

However, the royalty recipient is in a unique position compared to the other entities. While a Platform Freeze
would simply lead sellers to move to a new marketplace, most marketplaces support EIP-2981
which means that this denial could continue even in a different marketplace.

### Can you check if a transfer fails?

Solidity allows programmers to check if a transaction failed.
zang could theoretically ignore the failed money transfer and continue the sale.

However, consider a contract account that enters an infinite loop when receiving Ether.
Such contract would cause the overall transaction to fail due to running out of gas, regardless of
any possible checks.

In other words, it is impossible for zang to know in a finite amount of time if an arbitrary address refuses payment.

Side note: this is a special case of Rice's Theorem, which is itself a generalization of Turing's proof of the
undecidability of the halting problem.

### Mitigation

In order to prevent an attacker that compromised zang's commission account from executing a Platform Freeze attack, zang's owner must be able to
change zang's commission account.

The seller's Sale Denial attack, while unusual, doesn't represent a potential problem, since it is equivalent to a private sale.

To mitigate the royalty recipient Sale Denial, there are several possible solutions. The simplest one involves restricting royalties to only EOAs.
Pros:
- Prevents all Sale Denial attack, since EOAs always accept Ether
Cons:
- Prevents the usage of contracts that split royalty revenues
- Prevents DAOs from receiving royalties
- Prevents multisigs from receiving royalties
- Violates EIP-2981

Another option involves shifting the responsibility of checking the reliability of the NFT to the buyer.
While this is standard practice, this option doesn't prevent the following scenario:

- Alice mints an NFT and sets its royalty recipient to GenuineContract
- Bob audits GenuineContract and confirms that it's not malicious
- Bob purchases the NFT
- Alice sets the NFT's royalty recipient to MaliciousContract

In order to prevent this situation, we prevent the minter from editing the royalty recipient after minting.

## Commission Fraud

Description: A type of attack that involves manipulating commissions to obtain unfair deals.

During a sale, in addition to the seller, two other entities receive a share of the sale amount:
- zang's commission account
- the royalty recipient

Both variants of the attack involve altering the share in order to extract money from the seller.

### zang

Suppose that Alice lists an NFT on zang. In this example scenario, zang charges 5% on sales.
After listing the NFT, zang's owner increases fees to 100%.

If Bob purchases Alice's NFT, zang will receive the entirety of the sale amount.
On the other hand, zang's owner could directly purchase Alice's NFT, acquiring it without paying a single wei to
Alice.

### Royalty recipient

The same attack can be performed by editing the royalty percentage. However, such an attack would also affect
markeplaces beyond zang's, since most marketplaces implement EIP-2981.

Another important difference is the fact that while a seller, after finding out that zang has executed a Commission Fraud
attack, could (given enought time) delist their NFTs and transfer them to a different marketplace, the same attack executed
by a royalty recipient would make the NFT fundamentally worthless (from a financial point of view), since no one would be
able to sell it and actually receive the appropriate sale amount.

This can lead to situations such as the following:
- Alice mints an NFT and sets its royalty percentage to 5%
- Bob purchases the NFT and lists it on a marketplace
- Alice messages Bob:
    - Alice tells Bob that an exploit allows her to steal all sale revenue through a Commission Fraud attack by setting the
      royalty percentage to 100%
    - Alice asks for a ransom in exchange for not activating the exploit.
- Bob can either:
    a. Reveal to the public the existence of the exploit (therefore killing any chances of someone buying the NFT), or
    b. Pay the ransom and sell the NFT to someone else
- Bob pays the ransom
- Bob sells the NFT to Charlie
- Alice messages Charlie, repeating the cycle

A milder form of this attack involves increasing the royalties to a reasonable but still higher percentage (e.g. from 5% to 10%).
For example:
- Alice mints an NFT and sets its royalty percentage to 5%
- Bob is willing to purchase the NFT if it means he can resell it while only paying 5% royalties
- Bob purchases the NFT
- Alice increases the royalty percentage to 10%
- If Bob knew that this could happen, he wouldn't have bought the NFT
- Bob has been therefore misled into buying an NFT based on false information

### Mitigation

#### zang

The strongest mitigation possible involves preventing zang's owner from increasing commissions. However, this would prevent
zang from changing its commission model. A compromise solution involves imposing a timelock on commission percentage
increases. In other words, zang's owner must wait a certain amount of time (e.g. 7 days) before the changes goes into effect.

This solution allows users to move to a different marketplace (either because zang's owner has executed a Commission Fraud attack
or because they simply believe the new commission to be too high), while still giving zang's owner enough freedom to adapt its
commission model.

#### Royalty recipient

On the other hand, using a timelock for higher royalties doesn't give the current owner of the NFT any way to mitigate the damage,
since the market price would be affected by the knowledge that the royalty percentage will increase. At its extreme, the knowledge
that 7 days from now the royalty percentage will increase to 100% makes today's market price of the NFT equal to zero.

The solution is therefore to prevent any increase of the royalty percentage, with or without a timelock.

## Note: Execution equivalency

An important security consideration for DAOs interacting with zang concerns the equivalency between
certain actions. For example, a seller executing a Sale Denial attack is equivalent to a seller never listing
the NFT in the first place. While this is a sufficient analysis for EOAs, DAOs might vote differently for
equivalent actions.

Continuing with the Sale Denial example, suppose that a DAO approves a proposal (P1) to list an NFT for sale.
Shortly after, the DAO approves a proposal (P2) to reject Ether payments. This means that all sales will fail.
In practice, P2 has overriden P1, even though DAO members might not be aware of P2's effects on P1.

While this is a trivial examples, scenarios like this should be kept in mind when dealing with more complex interactions
between DAOs and zang.
