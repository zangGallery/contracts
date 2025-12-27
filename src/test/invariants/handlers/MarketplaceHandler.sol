// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../../ZangNFT.sol";
import "../../../Marketplace.sol";

/// @title Handler contract for Marketplace invariant testing
/// @notice Provides bounded operations for stateful fuzz testing
contract MarketplaceHandler is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;

    // Ghost variables for tracking state
    uint256 public ghost_totalMinted;
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalListed;
    uint256 public ghost_totalDelisted;
    uint256 public ghost_totalPurchased;
    uint256 public ghost_totalSalesVolume;
    uint256 public ghost_totalPlatformFees;
    uint256 public ghost_totalRoyaltiesPaid;
    uint256 public ghost_totalSellerEarnings;

    // Track listing amounts per token
    mapping(uint256 => uint256) public ghost_tokenListedAmount;

    // Actor management
    address[] public actors;
    address internal currentActor;

    // Track which tokens exist
    uint256[] public mintedTokenIds;

    // Call counters for debugging
    uint256 public callCount_mint;
    uint256 public callCount_list;
    uint256 public callCount_buy;
    uint256 public callCount_delist;
    uint256 public callCount_transfer;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(ZangNFT _zangNFT, Marketplace _marketplace) {
        zangNFT = _zangNFT;
        marketplace = _marketplace;

        // Create actor addresses with ETH
        for (uint256 i = 1; i <= 10; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);
            vm.deal(actor, 1000 ether);
        }
    }

    /// @notice Mint new tokens
    function mint(uint256 actorSeed, uint256 amount, uint96 royaltyNumerator) external useActor(actorSeed) {
        amount = bound(amount, 1, 100);
        royaltyNumerator = uint96(bound(royaltyNumerator, 0, 10000));

        uint256 tokenId =
            zangNFT.mint("textURI", "title", "description", amount, royaltyNumerator, currentActor, "");

        mintedTokenIds.push(tokenId);
        ghost_totalMinted += amount;
        callCount_mint++;
    }

    /// @notice List tokens on marketplace
    function listToken(uint256 actorSeed, uint256 tokenSeed, uint256 price, uint256 amount)
        external
        useActor(actorSeed)
    {
        if (mintedTokenIds.length == 0) return;

        uint256 tokenId = mintedTokenIds[bound(tokenSeed, 0, mintedTokenIds.length - 1)];
        uint256 balance = zangNFT.balanceOf(currentActor, tokenId);

        if (balance == 0) return;

        amount = bound(amount, 1, balance);
        price = bound(price, 1 wei, 10 ether);

        zangNFT.setApprovalForAll(address(marketplace), true);

        try marketplace.listToken(tokenId, price, amount) {
            ghost_totalListed += amount;
            ghost_tokenListedAmount[tokenId] += amount;
            callCount_list++;
        } catch {}
    }

    /// @notice Buy tokens from marketplace
    function buyToken(uint256 actorSeed, uint256 tokenSeed, uint256 listingSeed, uint256 amount)
        external
        useActor(actorSeed)
    {
        if (mintedTokenIds.length == 0) return;

        uint256 tokenId = mintedTokenIds[bound(tokenSeed, 0, mintedTokenIds.length - 1)];
        uint256 listingCount = marketplace.listingCount(tokenId);

        if (listingCount == 0) return;

        uint256 listingId = bound(listingSeed, 0, listingCount - 1);

        (uint256 price, address seller, uint256 listedAmount) = marketplace.listings(tokenId, listingId);

        // Skip if listing is empty, seller is buyer, or no tokens available
        if (seller == address(0) || seller == currentActor || listedAmount == 0) return;

        amount = bound(amount, 1, listedAmount);
        uint256 totalCost = price * amount;

        if (currentActor.balance < totalCost) return;

        // Check seller still has tokens
        if (zangNFT.balanceOf(seller, tokenId) < amount) return;

        uint256 platformBalBefore = zangNFT.zangCommissionAccount().balance;

        try marketplace.buyToken{value: totalCost}(tokenId, listingId, amount) {
            ghost_totalPurchased += amount;
            ghost_totalSalesVolume += totalCost;
            ghost_tokenListedAmount[tokenId] -= amount;

            // Track platform fees
            uint256 platformFee = (totalCost * zangNFT.platformFeePercentage()) / 10000;
            ghost_totalPlatformFees += platformFee;

            callCount_buy++;
        } catch {}
    }

    /// @notice Delist tokens from marketplace
    function delistToken(uint256 actorSeed, uint256 tokenSeed, uint256 listingSeed) external useActor(actorSeed) {
        if (mintedTokenIds.length == 0) return;

        uint256 tokenId = mintedTokenIds[bound(tokenSeed, 0, mintedTokenIds.length - 1)];
        uint256 listingCount = marketplace.listingCount(tokenId);

        if (listingCount == 0) return;

        uint256 listingId = bound(listingSeed, 0, listingCount - 1);

        (, address seller, uint256 amount) = marketplace.listings(tokenId, listingId);

        if (seller != currentActor) return;

        zangNFT.setApprovalForAll(address(marketplace), true);

        try marketplace.delistToken(tokenId, listingId) {
            ghost_totalDelisted += amount;
            ghost_tokenListedAmount[tokenId] -= amount;
            callCount_delist++;
        } catch {}
    }

    /// @notice Transfer tokens between actors (can disrupt listings)
    function transferToken(uint256 fromSeed, uint256 toSeed, uint256 tokenSeed, uint256 amount)
        external
        useActor(fromSeed)
    {
        if (mintedTokenIds.length == 0) return;

        uint256 tokenId = mintedTokenIds[bound(tokenSeed, 0, mintedTokenIds.length - 1)];
        address to = actors[bound(toSeed, 0, actors.length - 1)];

        if (to == currentActor) return;

        uint256 balance = zangNFT.balanceOf(currentActor, tokenId);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        try zangNFT.safeTransferFrom(currentActor, to, tokenId, amount, "") {
            callCount_transfer++;
        } catch {}
    }

    /// @notice Burn tokens
    function burnToken(uint256 actorSeed, uint256 tokenSeed, uint256 amount) external useActor(actorSeed) {
        if (mintedTokenIds.length == 0) return;

        uint256 tokenId = mintedTokenIds[bound(tokenSeed, 0, mintedTokenIds.length - 1)];
        uint256 balance = zangNFT.balanceOf(currentActor, tokenId);

        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        try zangNFT.burn(currentActor, tokenId, amount) {
            ghost_totalBurned += amount;
        } catch {}
    }

    /// @notice Get the number of actors
    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Get the number of minted tokens
    function mintedTokenCount() external view returns (uint256) {
        return mintedTokenIds.length;
    }

    /// @notice Reduce an actor's balance for testing
    function reduceActorBalance(uint256 actorSeed, uint256 amount) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        if (actor.balance >= amount) {
            vm.prank(actor);
            payable(address(0xdead)).transfer(amount);
        }
    }
}
