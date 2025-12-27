// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Symbolic tests for Marketplace (Halmos)
/// @notice These tests use symbolic execution to explore all possible paths
contract MarketplaceSymbolicTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    address public platformAccount;

    function setUp() public {
        platformAccount = address(0x33D);
        zangNFT = new ZangNFT("ZangNFT", "ZNG", "desc", "img", "link", platformAccount);
        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
    }

    /// @notice Symbolic: Buyer always gets NFT or full refund
    /// @dev If buyToken succeeds, buyer has tokens. If it reverts, buyer keeps ETH.
    function check_buyerAlwaysGetsNFTOrRefund(
        uint256 price,
        uint256 amount,
        uint256 buyAmount
    ) public {
        // Bound inputs to reasonable ranges
        vm.assume(price > 0 && price <= 100 ether);
        vm.assume(amount > 0 && amount <= 100);
        vm.assume(buyAmount > 0 && buyAmount <= amount);

        address seller = address(0x1);
        address buyer = address(0x2);

        // Setup: seller mints and lists
        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);
        vm.stopPrank();

        // Buyer's initial state
        uint256 totalCost = price * buyAmount;
        vm.deal(buyer, totalCost);
        uint256 buyerEthBefore = buyer.balance;
        uint256 buyerNftBefore = zangNFT.balanceOf(buyer, tokenId);

        // Attempt purchase
        vm.prank(buyer);
        try marketplace.buyToken{value: totalCost}(tokenId, 0, buyAmount) {
            // Success: buyer must have received NFTs
            assert(zangNFT.balanceOf(buyer, tokenId) == buyerNftBefore + buyAmount);
        } catch {
            // Failure: buyer must still have their ETH
            assert(buyer.balance == buyerEthBefore);
        }
    }

    /// @notice Symbolic: Seller always gets payment or keeps NFT
    function check_sellerAlwaysGetsPaidOrKeepsNFT(
        uint256 price,
        uint256 amount,
        uint256 buyAmount
    ) public {
        vm.assume(price > 0 && price <= 100 ether);
        vm.assume(amount > 0 && amount <= 100);
        vm.assume(buyAmount > 0 && buyAmount <= amount);

        address seller = address(0x1);
        address buyer = address(0x2);

        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);
        vm.stopPrank();

        uint256 sellerEthBefore = seller.balance;
        uint256 sellerNftBefore = zangNFT.balanceOf(seller, tokenId);
        uint256 totalCost = price * buyAmount;

        vm.deal(buyer, totalCost);
        vm.prank(buyer);
        try marketplace.buyToken{value: totalCost}(tokenId, 0, buyAmount) {
            // Success: seller got paid (minus platform fee and royalty)
            assert(seller.balance > sellerEthBefore);
            // And seller lost NFTs
            assert(zangNFT.balanceOf(seller, tokenId) == sellerNftBefore - buyAmount);
        } catch {
            // Failure: seller still has NFTs
            assert(zangNFT.balanceOf(seller, tokenId) == sellerNftBefore);
        }
    }

    /// @notice Symbolic: ETH is conserved (no ETH stuck in marketplace)
    function check_noEthStuckInMarketplace(
        uint256 price,
        uint256 amount
    ) public {
        vm.assume(price > 0 && price <= 100 ether);
        vm.assume(amount > 0 && amount <= 100);

        address seller = address(0x1);
        address buyer = address(0x2);

        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);
        vm.stopPrank();

        uint256 marketplaceBalBefore = address(marketplace).balance;
        uint256 totalCost = price;

        vm.deal(buyer, totalCost);
        vm.prank(buyer);
        try marketplace.buyToken{value: totalCost}(tokenId, 0, 1) {} catch {}

        // Marketplace should never hold ETH
        assert(address(marketplace).balance == marketplaceBalBefore);
    }

    /// @notice Symbolic: Platform fee calculation never overflows
    function check_platformFeeNoOverflow(uint256 salePrice, uint16 feePercent) public {
        vm.assume(salePrice <= type(uint128).max);
        vm.assume(feePercent <= 10000);

        // This mirrors the calculation in _handleFunds
        uint256 platformFee = (salePrice * feePercent) / 10000;

        // Fee should never exceed sale price when fee <= 100%
        assert(platformFee <= salePrice);
    }

    /// @notice Symbolic: Royalty + platform fee never exceeds sale price (when fee <= 100%)
    function check_totalFeesNeverExceedPrice(
        uint256 salePrice,
        uint16 platformFeePercent,
        uint96 royaltyPercent
    ) public {
        vm.assume(salePrice > 0 && salePrice <= type(uint128).max);
        vm.assume(platformFeePercent <= 10000);
        vm.assume(royaltyPercent <= 10000);

        uint256 platformFee = (salePrice * platformFeePercent) / 10000;
        uint256 remainder = salePrice - platformFee;
        uint256 royaltyFee = (remainder * royaltyPercent) / 10000;

        // Total fees should not exceed sale price
        assert(platformFee + royaltyFee <= salePrice);
    }

    /// @notice Symbolic: Listing can only be modified by seller
    function check_onlySellerCanModifyListing(
        address caller,
        uint256 newPrice
    ) public {
        vm.assume(newPrice > 0);

        address seller = address(0x1);
        vm.assume(caller != seller);
        vm.assume(caller != address(0));

        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 10, 0, seller, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, 1 ether, 10);
        vm.stopPrank();

        // Non-seller should not be able to modify
        vm.prank(caller);
        try marketplace.editListingPrice(tokenId, 0, newPrice) {
            // Should never succeed
            assert(false);
        } catch {
            // Expected - non-seller cannot modify
        }
    }
}
