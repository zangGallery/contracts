// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Fuzz tests for ERC2981 royalty implementation
/// @notice Property-based tests for royalty calculations
contract RoyaltyFuzzTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    address public zangCommissionAccount;

    function setUp() public {
        zangCommissionAccount = address(0x33D);
        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);
        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
    }

    /// @notice Fuzz: Royalty percentage must be <= 100%
    function testFuzz_royaltyBounded(uint96 royaltyNumerator) public {
        address minter = address(0x1);

        vm.prank(minter);
        if (royaltyNumerator > 10000) {
            vm.expectRevert("ERC2981: royalty fee will exceed salePrice");
            zangNFT.mint("text", "title", "desc", 1, royaltyNumerator, minter, "");
        } else {
            uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, royaltyNumerator, minter, "");
            assertEq(zangNFT.royaltyNumerator(tokenId), royaltyNumerator);
        }
    }

    /// @notice Fuzz: Royalty receiver cannot be zero address
    function testFuzz_royaltyReceiverNotZero(address receiver) public {
        address minter = address(0x1);

        vm.prank(minter);
        if (receiver == address(0)) {
            vm.expectRevert("ERC2981: invalid parameters");
            zangNFT.mint("text", "title", "desc", 1, 1000, receiver, "");
        } else {
            uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 1000, receiver, "");
            (address royaltyReceiver, ) = zangNFT.royaltyInfo(tokenId, 10000);
            assertEq(royaltyReceiver, receiver);
        }
    }

    /// @notice Fuzz: Royalty calculation correctness
    function testFuzz_royaltyCalculation(uint96 royaltyNumerator, uint256 salePrice) public {
        royaltyNumerator = uint96(bound(royaltyNumerator, 0, 10000));
        salePrice = bound(salePrice, 1, type(uint128).max);

        address minter = address(0x1);
        address royaltyReceiver = address(0x2);

        vm.prank(minter);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, royaltyNumerator, royaltyReceiver, "");

        (address receiver, uint256 royaltyAmount) = zangNFT.royaltyInfo(tokenId, salePrice);

        assertEq(receiver, royaltyReceiver);

        uint256 expectedRoyalty = (salePrice * royaltyNumerator) / 10000;
        assertEq(royaltyAmount, expectedRoyalty);

        // Royalty should never exceed sale price
        assertLe(royaltyAmount, salePrice);
    }

    /// @notice Fuzz: Royalty can only decrease
    function testFuzz_royaltyOnlyDecreases(uint96 initialRoyalty, uint96 newRoyalty) public {
        initialRoyalty = uint96(bound(initialRoyalty, 1, 10000));

        address minter = address(0x1);

        vm.startPrank(minter);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, initialRoyalty, minter, "");

        if (newRoyalty >= initialRoyalty) {
            vm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
            zangNFT.decreaseRoyaltyNumerator(tokenId, newRoyalty);
        } else {
            zangNFT.decreaseRoyaltyNumerator(tokenId, newRoyalty);
            assertEq(zangNFT.royaltyNumerator(tokenId), newRoyalty);
        }
        vm.stopPrank();
    }

    /// @notice Fuzz: Only author can decrease royalty
    function testFuzz_onlyAuthorDecreasesRoyalty(address caller) public {
        address author = address(0x1);
        vm.assume(caller != author);
        vm.assume(caller != address(0));

        vm.prank(author);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 1000, author, "");

        vm.prank(caller);
        vm.expectRevert("ZangNFT: caller is not author");
        zangNFT.decreaseRoyaltyNumerator(tokenId, 500);
    }

    /// @notice Fuzz: Full royalty distribution in marketplace
    function testFuzz_royaltyDistributionInMarketplace(uint96 royaltyNumerator, uint256 salePrice) public {
        royaltyNumerator = uint96(bound(royaltyNumerator, 0, 10000));
        salePrice = bound(salePrice, 10000, 100 ether); // Minimum to avoid rounding issues

        address minter = address(0x1);
        address seller = address(0x2);
        address buyer = address(0x3);
        address royaltyReceiver = address(0x4);

        // Minter creates token with royalty, transfers to seller
        vm.prank(minter);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, royaltyNumerator, royaltyReceiver, "");

        vm.prank(minter);
        zangNFT.safeTransferFrom(minter, seller, tokenId, 1, "");

        // Seller lists
        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, salePrice, 1);
        vm.stopPrank();

        // Track balances
        uint256 platformBalBefore = zangCommissionAccount.balance;
        uint256 royaltyBalBefore = royaltyReceiver.balance;
        uint256 sellerBalBefore = seller.balance;

        // Buyer purchases
        vm.deal(buyer, salePrice);
        vm.prank(buyer);
        marketplace.buyToken{value: salePrice}(tokenId, 0, 1);

        // Calculate expected distribution (as done in Marketplace)
        uint256 platformFee = (salePrice * zangNFT.platformFeePercentage()) / 10000;
        uint256 remainder = salePrice - platformFee;

        // Note: Royalty is calculated on REMAINDER, not full price (non-standard ERC2981)
        uint256 expectedRoyalty = (remainder * royaltyNumerator) / 10000;
        uint256 expectedSellerAmount = remainder - expectedRoyalty;

        // Verify distribution
        assertEq(zangCommissionAccount.balance - platformBalBefore, platformFee, "Platform fee incorrect");

        if (royaltyNumerator > 0) {
            assertEq(royaltyReceiver.balance - royaltyBalBefore, expectedRoyalty, "Royalty incorrect");
        }

        assertEq(seller.balance - sellerBalBefore, expectedSellerAmount, "Seller amount incorrect");

        // Total conservation
        uint256 totalDistributed = platformFee + expectedRoyalty + expectedSellerAmount;
        assertEq(totalDistributed, salePrice, "Total not conserved");
    }

    /// @notice Fuzz: Small amounts and rounding
    function testFuzz_smallAmountsAndRounding(uint256 salePrice) public {
        salePrice = bound(salePrice, 1, 1000); // Small amounts

        address minter = address(0x1);
        address seller = address(0x2);
        address buyer = address(0x3);

        vm.prank(minter);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 1000, minter, ""); // 10% royalty

        vm.prank(minter);
        zangNFT.safeTransferFrom(minter, seller, tokenId, 1, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, salePrice, 1);
        vm.stopPrank();

        uint256 totalBefore = zangCommissionAccount.balance + minter.balance + seller.balance;

        vm.deal(buyer, salePrice);
        vm.prank(buyer);
        marketplace.buyToken{value: salePrice}(tokenId, 0, 1);

        uint256 totalAfter = zangCommissionAccount.balance + minter.balance + seller.balance;

        // All ETH should be distributed
        assertEq(totalAfter - totalBefore, salePrice, "ETH lost to rounding");
    }

    /// @notice Fuzz: Zero royalty handling
    function testFuzz_zeroRoyaltyHandling(uint256 salePrice) public {
        salePrice = bound(salePrice, 1, 100 ether);

        address seller = address(0x1);
        address buyer = address(0x2);

        // Zero royalty
        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 0, seller, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, salePrice, 1);
        vm.stopPrank();

        uint256 platformBalBefore = zangCommissionAccount.balance;
        uint256 sellerBalBefore = seller.balance;

        vm.deal(buyer, salePrice);
        vm.prank(buyer);
        marketplace.buyToken{value: salePrice}(tokenId, 0, 1);

        uint256 platformFee = (salePrice * zangNFT.platformFeePercentage()) / 10000;
        uint256 sellerAmount = salePrice - platformFee;

        assertEq(zangCommissionAccount.balance - platformBalBefore, platformFee);
        assertEq(seller.balance - sellerBalBefore, sellerAmount);
    }

    /// @notice Fuzz: 100% royalty (extreme case)
    function testFuzz_maxRoyalty(uint256 salePrice) public {
        salePrice = bound(salePrice, 10000, 100 ether);

        address minter = address(0x1);
        address seller = address(0x2);
        address buyer = address(0x3);

        // 100% royalty
        vm.prank(minter);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 10000, minter, "");

        vm.prank(minter);
        zangNFT.safeTransferFrom(minter, seller, tokenId, 1, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, salePrice, 1);
        vm.stopPrank();

        uint256 sellerBalBefore = seller.balance;

        vm.deal(buyer, salePrice);
        vm.prank(buyer);
        marketplace.buyToken{value: salePrice}(tokenId, 0, 1);

        // At 100% royalty, seller gets nothing (after platform fee)
        uint256 sellerReceived = seller.balance - sellerBalBefore;
        assertEq(sellerReceived, 0, "Seller should get nothing at 100% royalty");
    }
}
