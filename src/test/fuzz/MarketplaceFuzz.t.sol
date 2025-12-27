// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Fuzz tests for Marketplace contract
/// @notice Property-based tests for marketplace operations
contract MarketplaceFuzzTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    address public zangCommissionAccount;
    address public seller;
    address public buyer;

    function setUp() public {
        zangCommissionAccount = address(0x33D);
        seller = address(0x1);
        buyer = address(0x2);

        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);

        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
    }

    /// @notice Fuzz: Listing amount should never exceed token balance
    function testFuzz_listingAmountBoundedByBalance(uint256 mintAmount, uint256 listAmount) public {
        mintAmount = bound(mintAmount, 1, 10000);
        listAmount = bound(listAmount, 1, mintAmount + 100);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", mintAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);

        if (listAmount > mintAmount) {
            vm.expectRevert("Marketplace: not enough tokens to list");
            marketplace.listToken(tokenId, 1 ether, listAmount);
        } else {
            marketplace.listToken(tokenId, 1 ether, listAmount);
            (, , uint256 listedAmount) = marketplace.listings(tokenId, 0);
            assertEq(listedAmount, listAmount);
        }
        vm.stopPrank();
    }

    /// @notice Fuzz: Price * amount should not overflow (and purchase should work)
    function testFuzz_purchasePriceCalculation(uint128 price, uint64 amount) public {
        vm.assume(price > 0);
        vm.assume(amount > 0);

        uint256 totalCost = uint256(price) * uint256(amount);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);
        vm.stopPrank();

        vm.deal(buyer, totalCost);
        vm.prank(buyer);
        marketplace.buyToken{value: totalCost}(tokenId, 0, amount);

        assertEq(zangNFT.balanceOf(buyer, tokenId), amount);
    }

    /// @notice Fuzz: Partial purchases should update listing correctly
    function testFuzz_partialPurchaseUpdatesListing(uint256 listAmount, uint256 buyAmount) public {
        listAmount = bound(listAmount, 2, 1000);
        buyAmount = bound(buyAmount, 1, listAmount - 1);

        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", listAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, listAmount);
        vm.stopPrank();

        vm.deal(buyer, price * buyAmount);
        vm.prank(buyer);
        marketplace.buyToken{value: price * buyAmount}(tokenId, 0, buyAmount);

        (, address listedSeller, uint256 remaining) = marketplace.listings(tokenId, 0);
        assertEq(listedSeller, seller, "Seller should remain");
        assertEq(remaining, listAmount - buyAmount, "Remaining should decrease");
    }

    /// @notice Fuzz: Full purchase should delist token
    function testFuzz_fullPurchaseDelists(uint256 amount) public {
        amount = bound(amount, 1, 1000);
        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);
        vm.stopPrank();

        vm.deal(buyer, price * amount);
        vm.prank(buyer);
        marketplace.buyToken{value: price * amount}(tokenId, 0, amount);

        (, address listedSeller, uint256 remaining) = marketplace.listings(tokenId, 0);
        assertEq(listedSeller, address(0), "Seller should be zero (delisted)");
        assertEq(remaining, 0, "Amount should be zero");
    }

    /// @notice Fuzz: ETH distribution should conserve total value
    function testFuzz_ethConservation(uint256 salePrice, uint96 royaltyPercent) public {
        salePrice = bound(salePrice, 1000, 100 ether); // Minimum to avoid rounding to zero
        royaltyPercent = uint96(bound(royaltyPercent, 0, 10000));

        address creator = address(0x3);

        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, royaltyPercent, creator, "");

        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, salePrice, 1);
        vm.stopPrank();

        uint256 platformBalBefore = zangCommissionAccount.balance;
        uint256 creatorBalBefore = creator.balance;
        uint256 sellerBalBefore = seller.balance;

        vm.deal(buyer, salePrice);
        vm.prank(buyer);
        marketplace.buyToken{value: salePrice}(tokenId, 0, 1);

        uint256 platformReceived = zangCommissionAccount.balance - platformBalBefore;
        uint256 creatorReceived = creator.balance - creatorBalBefore;
        uint256 sellerReceived = seller.balance - sellerBalBefore;

        // Total received should equal sale price
        assertEq(platformReceived + creatorReceived + sellerReceived, salePrice, "ETH not conserved");
    }

    /// @notice Fuzz: Multiple listings for same token
    function testFuzz_multipleListings(uint8 numListings, uint256 totalAmount) public {
        numListings = uint8(bound(numListings, 1, 10));
        totalAmount = bound(totalAmount, numListings, 1000);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", totalAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);

        uint256 amountPerListing = totalAmount / numListings;

        for (uint8 i = 0; i < numListings; i++) {
            marketplace.listToken(tokenId, (i + 1) * 0.1 ether, amountPerListing);
        }

        assertEq(marketplace.listingCount(tokenId), numListings);
        vm.stopPrank();
    }

    /// @notice Fuzz: Cannot buy more than listed
    function testFuzz_cannotBuyMoreThanListed(uint256 listAmount, uint256 buyAmount) public {
        listAmount = bound(listAmount, 1, 100);
        buyAmount = bound(buyAmount, listAmount + 1, listAmount + 100);

        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", listAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, listAmount);
        vm.stopPrank();

        vm.deal(buyer, price * buyAmount);
        vm.prank(buyer);
        vm.expectRevert("Marketplace: not enough tokens to buy");
        marketplace.buyToken{value: price * buyAmount}(tokenId, 0, buyAmount);
    }

    /// @notice Fuzz: Cannot buy from self
    function testFuzz_cannotBuyFromSelf(uint256 amount, uint256 price) public {
        amount = bound(amount, 1, 100);
        price = bound(price, 1, 10 ether);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", amount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, amount);

        vm.deal(seller, price * amount);
        vm.expectRevert("Marketplace: cannot buy from yourself");
        marketplace.buyToken{value: price * amount}(tokenId, 0, amount);
        vm.stopPrank();
    }

    /// @notice Fuzz: Seller token transfer invalidates listing
    function testFuzz_sellerTransferInvalidatesListing(uint256 listAmount, uint256 transferAmount) public {
        listAmount = bound(listAmount, 2, 100);
        transferAmount = bound(transferAmount, 1, listAmount);

        uint256 price = 1 ether;
        address recipient = address(0x4);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", listAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, listAmount);

        // Transfer some tokens away
        zangNFT.safeTransferFrom(seller, recipient, tokenId, transferAmount, "");
        vm.stopPrank();

        // Try to buy full listed amount - should fail if transferred amount makes seller insufficient
        vm.deal(buyer, price * listAmount);
        vm.prank(buyer);

        if (listAmount - transferAmount < listAmount) {
            vm.expectRevert("Marketplace: seller does not have enough tokens");
            marketplace.buyToken{value: price * listAmount}(tokenId, 0, listAmount);
        }
    }

    /// @notice Fuzz: Edit listing price
    function testFuzz_editListingPrice(uint256 originalPrice, uint256 newPrice) public {
        originalPrice = bound(originalPrice, 1, 10 ether);
        newPrice = bound(newPrice, 1, 10 ether);
        vm.assume(newPrice != originalPrice);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 10, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, originalPrice, 10);

        marketplace.editListingPrice(tokenId, 0, newPrice);

        (uint256 listedPrice, , ) = marketplace.listings(tokenId, 0);
        assertEq(listedPrice, newPrice);
        vm.stopPrank();
    }

    /// @notice Fuzz: Edit listing amount
    function testFuzz_editListingAmount(uint256 originalAmount, uint256 newAmount) public {
        originalAmount = bound(originalAmount, 1, 50);
        newAmount = bound(newAmount, 1, 100);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 100, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, 1 ether, originalAmount);

        marketplace.editListingAmount(tokenId, 0, newAmount, originalAmount);

        (, , uint256 listedAmount) = marketplace.listings(tokenId, 0);
        assertEq(listedAmount, newAmount);
        vm.stopPrank();
    }
}
