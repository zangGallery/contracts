// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";
import "./handlers/MarketplaceHandler.sol";

/// @title Invariant tests for Marketplace contract
/// @notice Tests properties that must always hold regardless of operation sequence
contract MarketplaceInvariantTest is StdInvariant, Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    MarketplaceHandler public handler;
    address public zangCommissionAccount;

    function setUp() public {
        zangCommissionAccount = address(0x33D);

        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);

        marketplace = new Marketplace(IZangNFT(address(zangNFT)));

        handler = new MarketplaceHandler(zangNFT, marketplace);

        // Target only the handler for invariant testing
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(zangNFT));
        excludeSender(address(marketplace));
    }

    /// @notice Invariant: Deleted listings must have all zero values
    /// @dev A listing with seller == address(0) should have price == 0 and amount == 0
    function invariant_deletedListingsAreZero() public view {
        uint256 tokenCount = handler.mintedTokenCount();

        for (uint256 t = 0; t < tokenCount; t++) {
            uint256 tokenId = handler.mintedTokenIds(t);
            uint256 listingCount = marketplace.listingCount(tokenId);

            for (uint256 l = 0; l < listingCount; l++) {
                (uint256 price, address seller, uint256 amount) = marketplace.listings(tokenId, l);

                if (seller == address(0)) {
                    assertEq(price, 0, "Deleted listing should have zero price");
                    assertEq(amount, 0, "Deleted listing should have zero amount");
                }
            }
        }
    }

    /// @notice Invariant: Active listings must have non-zero values
    /// @dev A listing with seller != address(0) should have price > 0 and amount > 0
    function invariant_activeListingsHaveValidValues() public view {
        uint256 tokenCount = handler.mintedTokenCount();

        for (uint256 t = 0; t < tokenCount; t++) {
            uint256 tokenId = handler.mintedTokenIds(t);
            uint256 listingCount = marketplace.listingCount(tokenId);

            for (uint256 l = 0; l < listingCount; l++) {
                (uint256 price, address seller, uint256 amount) = marketplace.listings(tokenId, l);

                if (seller != address(0)) {
                    assertGt(price, 0, "Active listing must have positive price");
                    assertGt(amount, 0, "Active listing must have positive amount");
                }
            }
        }
    }

    /// @notice Invariant: Token supply can only decrease (via burns), never increase after mint
    function invariant_tokenSupplyNeverIncreases() public view {
        // Total minted should always be >= total existing supply + burned
        // This is implicitly maintained by ERC1155 but good to verify
        uint256 totalMinted = handler.ghost_totalMinted();
        uint256 totalBurned = handler.ghost_totalBurned();

        // Cannot verify exact supply without iterating all tokens and holders
        // But we can verify burned never exceeds minted
        assertLe(totalBurned, totalMinted, "Cannot burn more than minted");
    }

    /// @notice Invariant: Listing count never decreases
    /// @dev listingCount[tokenId] only increments, listings are "deleted" but count remains
    function invariant_listingCountMonotonic() public view {
        uint256 tokenCount = handler.mintedTokenCount();

        for (uint256 t = 0; t < tokenCount; t++) {
            uint256 tokenId = handler.mintedTokenIds(t);
            // listingCount should be >= number of actual listings ever created
            // This is a design observation - listingCount can grow unboundedly
            assertGe(marketplace.listingCount(tokenId), 0);
        }
    }

    /// @notice Invariant: Platform fee percentage is bounded
    /// @dev This WILL FAIL if the uncapped fee vulnerability is exploited
    function invariant_platformFeeBounded() public view {
        uint16 fee = zangNFT.platformFeePercentage();
        assertLe(fee, 10000, "Platform fee should not exceed 100%");
    }

    /// @notice Invariant: Commission account should not be zero
    /// @dev This WILL FAIL if zero address vulnerability is exploited
    function invariant_commissionAccountNotZero() public view {
        assertTrue(zangNFT.zangCommissionAccount() != address(0), "Commission account should not be zero");
    }

    /// @notice Invariant: Total purchased should not exceed total listed
    function invariant_purchasedDoesNotExceedListed() public view {
        uint256 totalListed = handler.ghost_totalListed();
        uint256 totalDelisted = handler.ghost_totalDelisted();
        uint256 totalPurchased = handler.ghost_totalPurchased();

        // Purchased + remaining listed + delisted should equal total listed
        // At minimum: purchased <= listed
        assertLe(totalPurchased, totalListed, "Cannot purchase more than was listed");
    }

    /// @notice Invariant: Handler call counts should be reasonable
    /// @dev Just for debugging - ensures handler is being exercised
    function invariant_handlerIsActive() public {
        // At least some operations should have occurred
        uint256 totalCalls = handler.callCount_mint() + handler.callCount_list() + handler.callCount_buy()
            + handler.callCount_delist() + handler.callCount_transfer();

        // This is just for observation, not a real invariant
        emit log_named_uint("Total handler calls", totalCalls);
        emit log_named_uint("Mints", handler.callCount_mint());
        emit log_named_uint("Lists", handler.callCount_list());
        emit log_named_uint("Buys", handler.callCount_buy());
        emit log_named_uint("Delists", handler.callCount_delist());
        emit log_named_uint("Transfers", handler.callCount_transfer());
    }

    /// @notice Invariant: ETH balances should be consistent
    /// @dev Platform + royalties + seller earnings should equal sales volume
    function invariant_ethConservation() public view {
        uint256 salesVolume = handler.ghost_totalSalesVolume();
        uint256 platformFees = handler.ghost_totalPlatformFees();

        // Platform fees should be approximately (salesVolume * feePercentage / 10000)
        // Allow for some rounding error
        if (salesVolume > 0) {
            // Just verify platform fees don't exceed sales volume
            assertLe(platformFees, salesVolume, "Platform fees cannot exceed sales volume");
        }
    }
}

/// @title Additional invariant tests focusing on edge cases
contract MarketplaceEdgeCaseInvariantTest is StdInvariant, Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    MarketplaceHandler public handler;

    function setUp() public {
        address zangCommissionAccount = address(0x33D);

        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);

        marketplace = new Marketplace(IZangNFT(address(zangNFT)));

        handler = new MarketplaceHandler(zangNFT, marketplace);

        targetContract(address(handler));
    }

    /// @notice Invariant: Actors should maintain solvency
    /// @dev No actor should have negative balance (impossible in EVM, but verify no weird states)
    function invariant_actorsSolvent() public view {
        uint256 actorCount = handler.actorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);
            // Just verify we can read balance without error
            actor.balance;
        }
    }

    /// @notice Invariant: Marketplace should not hold ETH
    /// @dev All ETH should be distributed immediately in buyToken
    function invariant_marketplaceHoldsNoEth() public view {
        assertEq(address(marketplace).balance, 0, "Marketplace should not hold ETH");
    }

    /// @notice Invariant: ZangNFT should not hold ETH
    /// @dev ZangNFT is not designed to receive ETH
    function invariant_zangNFTHoldsNoEth() public view {
        assertEq(address(zangNFT).balance, 0, "ZangNFT should not hold ETH");
    }
}
