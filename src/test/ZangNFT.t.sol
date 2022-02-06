// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "ds-test/test.sol";

import "../ZangNFT.sol";
import "../Marketplace.sol";
import {StringUtils} from "../StringUtils.sol";

interface Hevm {
    function prank(address) external;
    function expectRevert(bytes calldata) external;
    function deal(address, uint256) external;
    function startPrank(address) external;
    function stopPrank() external;
    function warp(uint256) external;
}

contract ZangNFTtest is DSTest {
    ZangNFT zangNFT;
    Marketplace marketplace;
    Hevm constant hevm = Hevm(HEVM_ADDRESS);
    address zangCommissionAccount = address(0x33D);
    struct Listing {
        uint256 price;
        address seller;
        uint256 amount;
    }

    function setUp() public {
        zangNFT = new ZangNFT(
            "ZangNFT",
            "ZNG",
            "zang description",
            "zang image uri",
            "zang external link",
            zangCommissionAccount);
        IZangNFT izang = IZangNFT(address(zangNFT));
        marketplace = new Marketplace(izang);
    }

    function test_metadata() public {
        string memory expectedName = "ZangNFT";
        assertEq(zangNFT.name(), expectedName);

        string memory expectedSymbol = "ZNG";
        assertEq(zangNFT.symbol(), expectedSymbol);

        string memory expectedDescription = "zang description";
        assertEq(zangNFT.description(), expectedDescription);

        string memory expectedImageUri = "zang image uri";
        assertEq(zangNFT.imageURI(), expectedImageUri);

        string memory expectedExternalLink = "zang external link";
        assertEq(zangNFT.externalLink(), expectedExternalLink);

        assertEq(zangNFT.zangCommissionAccount(), zangCommissionAccount);

        // Original string: '{"name": "ZangNFT", "description": "zang description", "image": "zang image uri", "external_link": "zang external link", "seller_fee_basis_points" : 500, "fee_recipient": "0x000000000000000000000000000000000000033d"}'
        // Base64 encoded string: eyJuYW1lIjogIlphbmdORlQiLCAiZGVzY3JpcHRpb24iOiAiemFuZyBkZXNjcmlwdGlvbiIsICJpbWFnZSI6ICJ6YW5nIGltYWdlIHVyaSIsICJleHRlcm5hbF9saW5rIjogInphbmcgZXh0ZXJuYWwgbGluayIsICJzZWxsZXJfZmVlX2Jhc2lzX3BvaW50cyIgOiA1MDAsICJmZWVfcmVjaXBpZW50IjogIjB4MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDMzZCJ9

        string memory expectedContractURI = "data:application/json;base64,eyJuYW1lIjogIlphbmdORlQiLCAiZGVzY3JpcHRpb24iOiAiemFuZyBkZXNjcmlwdGlvbiIsICJpbWFnZSI6ICJ6YW5nIGltYWdlIHVyaSIsICJleHRlcm5hbF9saW5rIjogInphbmcgZXh0ZXJuYWwgbGluayIsICJzZWxsZXJfZmVlX2Jhc2lzX3BvaW50cyIgOiA1MDAsICJmZWVfcmVjaXBpZW50IjogIjB4MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDMzZCJ9";

        assertEq(zangNFT.contractURI(), expectedContractURI);

    }

    function test_mint(string memory preTextURI, string memory title, string memory description, uint amount) public {
        address user = address(69);
        uint96 royaltyNumerator = 1000;
        hevm.startPrank(user);
        uint preBalance = zangNFT.balanceOf(user, 1);
        uint id = zangNFT.mint(preTextURI, title, description, amount, royaltyNumerator, address(0x1), "");
        uint postBalance = zangNFT.balanceOf(user, id);
        assertEq(preBalance + amount, postBalance);
        assertEq(zangNFT.lastTokenId(), id);
        address author = zangNFT.authorOf(id);
        assertEq(author, user);
        string memory postTextURI = zangNFT.textURI(id);
        assertEq(postTextURI, preTextURI);
        assertEq(zangNFT.nameOf(id), title);
        assertEq(zangNFT.descriptionOf(id), description);
        assertEq(zangNFT.royaltyNumerator(id), royaltyNumerator);
        assertEq(zangNFT.royaltyDenominator(), 10000);
        (address royaltyRecipient, uint256 royaltyAmount) = zangNFT.royaltyInfo(id, 10000);
        assertEq(royaltyRecipient, address(0x1));
        assertEq(royaltyAmount, 1000);
        (royaltyRecipient, royaltyAmount) = zangNFT.royaltyInfo(id, 20000);
        assertEq(royaltyAmount, 2000);
        (royaltyRecipient, royaltyAmount) = zangNFT.royaltyInfo(id, 10);
        assertEq(royaltyAmount, 1);
        hevm.stopPrank();
    }

    function testFail_exists_token_without_mints(uint tokenId) public {
        assertTrue(zangNFT.exists(tokenId));
    }

    function test_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint numTokens = 10;
        uint id = zangNFT.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, numTokens);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(id, 0);
        assertEq(price, 100);
        assertEq(seller, user);
        assertEq(amount, numTokens);
        hevm.stopPrank();
    }

    function test_listing_non_existent_token() public {
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.listToken(0, 100, 10);
    }

    function test_listing_more_than_owned() public {
        hevm.startPrank(address(69));
        uint numTokens = 10;
        uint id = zangNFT.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Marketplace: not enough tokens to list");
        marketplace.listToken(id, 100, numTokens + 1);
        hevm.stopPrank();
    }

    function test_listing_without_approval() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.listToken(id, 100, 10);
        hevm.stopPrank();
    }

    function test_listing_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Marketplace: amount must be greater than 0");
        marketplace.listToken(id, 100, 0);
        hevm.stopPrank();
    }

    function test_listing_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Marketplace: price must be greater than 0");
        marketplace.listToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_list_two_tokens() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id1 = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        uint id2 = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id1, 100, 10);
        marketplace.listToken(id2, 200, 10);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(id1, 0);
        assertEq(price, 100);
        assertEq(seller, user);
        assertEq(amount, 10);
        (price, seller, amount) = marketplace.listings(id2, 0);
        assertEq(price, 200);
        assertEq(seller, user);
        assertEq(amount, 10);
        hevm.stopPrank();
    }

    function test_two_listings_for_same_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        marketplace.listToken(id, 200, 10);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(id, 0);
        assertEq(price, 100);
        assertEq(seller, user);
        assertEq(amount, 10);
        (price, seller, amount) = marketplace.listings(id, 1);
        assertEq(price, 200);
        assertEq(seller, user);
        assertEq(amount, 10);
        hevm.stopPrank();
    }

    function test_delist_token() public {
        address user = address(69);
        hevm.startPrank(user);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(1, 0);
        assertEq(price, 0);
        assertEq(seller, address(0x0));
        assertEq(amount, 0);

        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        assertEq(id, 1);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        (price, seller, amount) = marketplace.listings(id, 0);
        assertEq(price, 100);
        assertEq(seller, user);
        assertEq(amount, 10);

        marketplace.delistToken(id, 0);
        (price, seller, amount) = marketplace.listings(id, 0);
        assertEq(price, 0);
        assertEq(seller, address(0x0));
        assertEq(amount, 0);
        hevm.stopPrank();
    }

    function test_delist_nonexistent_listing() public {
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.delistToken(1, 0);
    }

    function test_delist_a_delisted_listing() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        marketplace.delistToken(id, 0);
        hevm.expectRevert("Marketplace: can only remove own listings");
        marketplace.delistToken(id, 0);
        hevm.stopPrank();
    }

    function test_delist_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("texturi", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        zangNFT.safeTransferFrom(user, address(1559), id, 10, "");
        hevm.stopPrank();
        hevm.prank(address(1559));

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.delistToken(id, 0);

        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only remove own listings");
        marketplace.delistToken(id, 0);
    }

    function test_buy_all_listed_token() public {
        address minter = address(1);
        uint amount = 10;
        hevm.startPrank(minter);
        uint id = zangNFT.mint("text", "title", "description", amount, 1000, address(0x1), "");
        assertEq(zangNFT.balanceOf(minter, id), amount);
        zangNFT.setApprovalForAll(address(marketplace), true);
        uint price = 1 ether;

        marketplace.listToken(id, price, amount);
        hevm.stopPrank();

        address buyer = address(2);
        hevm.startPrank(buyer);
        hevm.deal(buyer, 10 ether);
        marketplace.buyToken{value: 10 ether}(id, 0, 10);
        hevm.stopPrank();

        assertEq(buyer.balance, 0);
        assertEq(zangCommissionAccount.balance, 0.5 ether);
        assertEq(minter.balance, 9.5 ether);

        uint balance = zangNFT.balanceOf(buyer, id);
        assertEq(balance, 10);

        address seller;
        (price, seller, amount) = marketplace.listings(id, 0);
        assertEq(price, 0);
        assertEq(seller, address(0x0));
        assertEq(amount, 0);
    }

    function test_royalties() public {
        address minter = address(1);
        address receiver = address(2);
        address buyer = address(3);
        uint amount = 10;

        hevm.startPrank(minter);
        uint id = zangNFT.mint("text", "title", "description", amount, 1000, address(0x1), "");
        zangNFT.safeTransferFrom(minter, receiver, id, amount, "");
        hevm.stopPrank();

        hevm.startPrank(receiver);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, amount);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 10 ether);
        marketplace.buyToken{value: 10 ether}(id, 0, 10);
        hevm.stopPrank();

        // 10 Ether
        // 5% of 10 ETH = 0.5 ETH goes to zang
        // There's 9.5 ETH left
        // 10% of 9.5 ETH = 0.95 ETH goes to the minter
        // 90% of 9.5 ETH = 8.55 ETH goes to the seller

        assertEq(buyer.balance, 0);
        assertEq(zangCommissionAccount.balance, 0.5 ether);
        assertEq(minter.balance, 0.95 ether);
        assertEq(receiver.balance, 8.55 ether);
        assertEq(zangCommissionAccount.balance + minter.balance + receiver.balance, 10 ether);
    }

    function test_buy_nonexistent_listing() public {
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.buyToken(1, 0, 10);
    }

    function test_buy_delisted_listing() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        marketplace.delistToken(id, 0);
        hevm.expectRevert("Marketplace: cannot interact with a delisted listing");
        marketplace.buyToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_buy_own_listing() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        hevm.expectRevert("Marketplace: cannot buy from yourself");
        marketplace.buyToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_buy_more_than_listed() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        hevm.expectRevert("Marketplace: not enough tokens to buy");
        hevm.stopPrank();
        hevm.prank(address(1));
        marketplace.buyToken(id, 0, 11);
    }

    function test_seller_does_not_have_enough_tokens_anymore() public {
        address seller = address(1);
        address receiver = address(2);
        address buyer = address(3);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        zangNFT.safeTransferFrom(seller, receiver, id, 5, "");
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 10 ether);
        hevm.expectRevert("Marketplace: seller does not have enough tokens");
        marketplace.buyToken{value: 10 ether}(id, 0, 10);
        hevm.stopPrank();
    }

    function test_price_does_not_match() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 5 ether, 10);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        hevm.expectRevert("Marketplace: price does not match");
        marketplace.buyToken{value: 1 ether}(id, 0, 10);
        hevm.stopPrank();
    }

    function test_frontrun_buy_on_different_listing() public {
        address seller = address(1);
        address buyer1 = address(2);
        address buyer2 = address(3);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5); //listing 0
        marketplace.listToken(id, 2 ether, 5); //listing 1
        hevm.stopPrank();

        // suppose buyer 2 wants to buy listing 1 and launch the tx

        // buyer 1 frontruns buyer 1 and buys listing 0
        hevm.startPrank(buyer1);
        hevm.deal(buyer1, 5 ether);
        marketplace.buyToken{value: 5 ether}(id, 0, 5);
        hevm.stopPrank();

        // buyer 2 buys listing 1
        hevm.startPrank(buyer2);
        hevm.deal(buyer2, 10 ether);
        marketplace.buyToken{value: 10 ether}(id, 1, 5);
        hevm.stopPrank();

        assertEq(zangNFT.balanceOf(buyer1, id), 5);
        assertEq(zangNFT.balanceOf(buyer2, id), 5);
    }

    function test_edit_listing() public {
        address seller = address(1);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        marketplace.editListing(id, 0, 2 ether, 10, 5);
        hevm.stopPrank();

        uint price;
        uint amount;

        (price, seller, amount) = marketplace.listings(id, 0);
        assertEq(price, 2 ether);
        assertEq(seller, address(1));
        assertEq(amount, 10);
    }

    function test_edit_nonexistent_token() public {
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListing(1, 0, 2 ether, 10, 5);
    }

    function test_edit_listing_more_than_owned() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: not enough tokens to list");
        marketplace.editListing(id, 0, 2 ether, 11, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: amount must be greater than 0");
        marketplace.editListing(id, 0, 2 ether, 0, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: price must be greater than 0");
        marketplace.editListing(id, 0, 0 ether, 10, 5);
        hevm.stopPrank();
    }

    function test_edit_nonexistent_listing() public {
        hevm.startPrank(address(69));
        zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListing(1, 0, 2 ether, 10, 5);
        
        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListing(1, 0, 2 ether, 10, 5);
        hevm.stopPrank();
    }

    function test_edit_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        //zangNFT.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.startPrank(address(1));

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListing(id, 0, 2 ether, 10, 5);
        
        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListing(id, 0, 2 ether, 5, 5);

        hevm.stopPrank();
    }

    function test_edit_listing_with_wrong_expected_amount_because_of_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        marketplace.buyToken{value: 1 ether}(id, 0, 1);
        hevm.stopPrank();

        hevm.startPrank(seller);
        hevm.expectRevert("Marketplace: expected amount does not match");
        marketplace.editListing(id, 0, 2 ether, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_price() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        marketplace.editListingPrice(id, 0, 2 ether);

        (uint price, address seller, uint amount) = marketplace.listings(id, 0);
        assertEq(price, 2 ether);
        assertEq(seller, user);
        assertEq(amount, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_nonexistent_token() public {
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListingPrice(1, 0, 2 ether);
    }

    function test_edit_listing_price_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: price must be greater than 0");
        marketplace.editListingPrice(id, 0, 0 ether);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_nonexistent_listing() public {
        hevm.startPrank(address(69));
        zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListingPrice(1, 0, 2 ether);

        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListingPrice(1, 0, 2 ether);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        zangNFT.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.prank(address(1));

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListingPrice(id, 0, 2 ether);

        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListingPrice(id, 0, 2 ether);
    }

    function test_edit_listing_price_with_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        marketplace.buyToken{value: 1 ether}(id, 0, 1);
        hevm.stopPrank();

        hevm.startPrank(seller);
        marketplace.editListingPrice(id, 0, 2 ether);
        hevm.stopPrank();

        uint price;
        uint amount;
        (price, seller, amount) = marketplace.listings(id, 0);
        assertEq(price, 2 ether);
        assertEq(seller, address(seller));
        assertEq(amount, 4);
    }

    function test_edit_listing_amount() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        marketplace.editListingAmount(id, 0, 10, 5);

        (uint price, address seller, uint amount) = marketplace.listings(id, 0);
        assertEq(price, 1 ether);
        assertEq(seller, user);
        assertEq(amount, 10);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_of_nonexistent_token() public {
        hevm.startPrank(address(69));
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListingAmount(1, 0, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_with_more_than_owned() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: not enough tokens to list");
        marketplace.editListingAmount(id, 0, 11, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Marketplace: amount must be greater than 0");
        marketplace.editListingAmount(id, 0, 0, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_of_non_existent_listing() public {
        hevm.startPrank(address(69));
        zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListingAmount(1, 0, 5, 5);

        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListingAmount(1, 0, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_of_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        // zangNFT.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.startPrank(address(1));

        hevm.expectRevert("Marketplace: Marketplace contract is not approved");
        marketplace.editListingAmount(id, 0, 5, 5);

        zangNFT.setApprovalForAll(address(marketplace), true);

        hevm.expectRevert("Marketplace: can only edit own listings");
        marketplace.editListingAmount(id, 0, 5, 5);

        hevm.stopPrank();
    }

    function test_edit_listing_amount_with_wrong_expected_amount_because_of_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangNFT.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        marketplace.buyToken{value: 1 ether}(id, 0, 1);
        hevm.stopPrank();

        hevm.startPrank(seller);
        hevm.expectRevert("Marketplace: expected amount does not match");
        marketplace.editListingAmount(id, 0, 5, 5);
        hevm.stopPrank();
    }

    function test_burn_some() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.burn(user, id, 5);

        assertEq(zangNFT.totalSupply(id), 10);

        assertEq(zangNFT.textURI(id), "text");
        assertEq(zangNFT.nameOf(id), "title");
        assertEq(zangNFT.descriptionOf(id), "description");

        hevm.stopPrank();
    }

    function test_burn_all() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.burn(user, id, 15);

        hevm.expectRevert("ZangNFT: uri query for nonexistent token");
        zangNFT.uri(id);

        hevm.expectRevert("ZangNFT: name query for nonexistent token");
        zangNFT.nameOf(id);

        hevm.expectRevert("ZangNFT: description query for nonexistent token");
        zangNFT.descriptionOf(id);

        assertEq(zangNFT.totalSupply(id), 0);

        hevm.expectRevert("ZangNFT: author query for nonexistent token");
        zangNFT.authorOf(id);

        hevm.stopPrank();
    }

    function test_burn_someone_else_token() public {
        address user = address(69);
        hevm.prank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");

        address burner = address(420);
        hevm.startPrank(burner);

        hevm.expectRevert("ZangNFT: caller is not owner nor approved");
        zangNFT.burn(user, id, 5);

        assertEq(zangNFT.totalSupply(id), 15);

        hevm.stopPrank();
    }

    function test_burn_someone_else_token_while_approved() public {
        address user = address(69);
        address burner = address(420);

        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(burner, true);
        hevm.stopPrank();

        hevm.startPrank(burner);

        zangNFT.burn(user, id, 5);
        assertEq(zangNFT.totalSupply(id), 10);

        hevm.stopPrank();
    }

    function test_list_burned_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        zangNFT.burn(user, id, 5);
        hevm.expectRevert("Marketplace: not enough tokens to list");
        marketplace.listToken(id, 1 ether, 15);

        marketplace.listToken(id, 1 ether, 10);
        hevm.stopPrank();
    }

    function test_list_burned_all_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        zangNFT.burn(user, id, 15);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.listToken(id, 1 ether, 15);
        hevm.stopPrank();
    }

    function test_buy_listing_of_burned_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 15);
        zangNFT.burn(user, id, 5);
        hevm.stopPrank();

        address buyer = address(420);
        hevm.startPrank(buyer);
        hevm.deal(buyer, 15 ether);
        hevm.expectRevert("Marketplace: seller does not have enough tokens");
        marketplace.buyToken{value: 15 ether}(id, 0, 15);
        hevm.stopPrank();
    }

    function test_buy_listing_of_burned_all_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 15);
        zangNFT.burn(user, id, 15);
        hevm.stopPrank();

        address buyer = address(420);
        hevm.startPrank(buyer);
        hevm.deal(buyer, 15 ether);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.buyToken{value: 15 ether}(id, 0, 15);
        hevm.stopPrank();
    }

    function test_delist_listing_of_burned_all_token() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangNFT.mint("text", "title", "description", 15, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 15);
        zangNFT.burn(user, id, 15);

        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.delistToken(id, 0);

        hevm.stopPrank();
    }

    function test_change_zang_commission_account_as_owner() public {
        zangNFT.setZangCommissionAccount(address(0x1));
        assertEq(zangNFT.zangCommissionAccount(), address(0x1));
    }

    function test_change_zang_commission_account_as_not_owner() public {
        address user = address(69);
        hevm.startPrank(user);
        hevm.expectRevert("Ownable: caller is not the owner");
        zangNFT.setZangCommissionAccount(address(0x1));
        hevm.stopPrank();
    }

    function test_buy_with_small_wei() public {
        address user = address(69);
        hevm.startPrank(user);
        uint amount = 15;
        uint id = zangNFT.mint("text", "title", "description", amount, 1000, address(0x1), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        uint price = 3 wei;
        marketplace.listToken(id, price, amount);
        hevm.stopPrank();

        address buyer = address(420);
        hevm.startPrank(buyer);
        hevm.deal(buyer, price*amount);
        marketplace.buyToken{value: price*amount}(id, 0, 15);
        hevm.stopPrank();

        // 45 wei
        // 5% of commission: 5% of 45 wei = 2.25 wei -> 2 wei
        // 10% royaltes to 0x1: 10% of 43 wei = 4.3 wei -> 4 wei
        // remaining: 39 wei instead of 38.45 wei
        
        assertEq(address(zangNFT.zangCommissionAccount()).balance, 2 wei);
        assertEq(address(0x1).balance, 4 wei);
        assertEq(address(user).balance, 39 wei);
    }

    function test_decrease_royalty_value() public {
        address user = address(69);
        hevm.startPrank(user);
        uint amount = 15;
        // Royalty: 10%
        uint id = zangNFT.mint("text", "title", "description", amount, 1000, address(0x1), "");

        // 7.5%
        zangNFT.decreaseRoyaltyNumerator(id, 750);
        assertEq(zangNFT.royaltyNumerator(id), 750);

        // 10%
        hevm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
        zangNFT.decreaseRoyaltyNumerator(id, 1000);

        // 7.5%
        hevm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
        zangNFT.decreaseRoyaltyNumerator(id, 750);

        // 7.49%
        zangNFT.decreaseRoyaltyNumerator(id, 749);
        assertEq(zangNFT.royaltyNumerator(id), 749);

        // 100.1%
        hevm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
        zangNFT.decreaseRoyaltyNumerator(id, 10001);
    }

    function test_decrease_royalty_value_fuzz(uint96 _lowerValue) public {
        address user = address(69);
        hevm.startPrank(user);
        uint amount = 15;
        uint96 currentRoyaltyValue = 1000;
        uint id = zangNFT.mint("text", "title", "description", amount, currentRoyaltyValue, address(0x1), "");

        if(_lowerValue > 10000) {
            hevm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
            zangNFT.decreaseRoyaltyNumerator(id, _lowerValue);
        } else if(_lowerValue > currentRoyaltyValue) {
            hevm.expectRevert("ERC2981: _lowerFeeNumerator must be less than the current royaltyFraction");
            zangNFT.decreaseRoyaltyNumerator(id, _lowerValue);
        } else {
            zangNFT.decreaseRoyaltyNumerator(id, _lowerValue);
            assertEq(zangNFT.royaltyNumerator(id), _lowerValue);
        }
    }

    function test_decrease_royalty_value_nonexistent_token() public {
        hevm.expectRevert("ZangNFT: decreasing royalty numerator for nonexistent token");
        zangNFT.decreaseRoyaltyNumerator(0, 100);
    }

    function test_set_platform_fee_percentage() public {
        uint16 currentFee = zangNFT.platformFeePercentage();
        assertEq(currentFee, 500);

        hevm.expectRevert("ZangNFTCommissions: _lowerFeePercentage must be lower than the current platform fee percentage");
        zangNFT.decreasePlatformFeePercentage(500);

        hevm.expectRevert("ZangNFTCommissions: _higherFeePercentage must be higher than the current platform fee percentage");
        zangNFT.requestPlatformFeePercentageIncrease(500);

        zangNFT.decreasePlatformFeePercentage(100);
        assertEq(zangNFT.platformFeePercentage(), 100);

        zangNFT.decreasePlatformFeePercentage(0);
        assertEq(zangNFT.platformFeePercentage(), 0);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase must be first requested");
        zangNFT.applyPlatformFeePercentageIncrease();

        // Requesting an increase to 100 (i.e. 1%)
        zangNFT.requestPlatformFeePercentageIncrease(100);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
        zangNFT.applyPlatformFeePercentageIncrease();

        hevm.warp(block.timestamp + 1 days);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
        zangNFT.applyPlatformFeePercentageIncrease();

        hevm.warp(block.timestamp + 7 days);

        // Increase finally succeeds
        zangNFT.applyPlatformFeePercentageIncrease();
        assertEq(zangNFT.platformFeePercentage(), 100);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase must be first requested");
        zangNFT.applyPlatformFeePercentageIncrease();

        // Request a new increase, this time to 200 (i.e. 2%)
        zangNFT.requestPlatformFeePercentageIncrease(200);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
        zangNFT.applyPlatformFeePercentageIncrease();

        hevm.warp(block.timestamp + 1 days);

        hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
        zangNFT.applyPlatformFeePercentageIncrease();

        hevm.warp(block.timestamp + 7 days);

        // Increase finally succeeds
        zangNFT.applyPlatformFeePercentageIncrease();
        assertEq(zangNFT.platformFeePercentage(), 200);
    }

    function test_set_platform_fee_percentage_fuzz(uint16 newFeePercentage) public {
        uint16 currentFee = zangNFT.platformFeePercentage();
        if(newFeePercentage == currentFee) {
            hevm.expectRevert("ZangNFTCommissions: _lowerFeePercentage must be lower than the current platform fee percentage");
            zangNFT.decreasePlatformFeePercentage(newFeePercentage);

            hevm.expectRevert("ZangNFTCommissions: _higherFeePercentage must be higher than the current platform fee percentage");
            zangNFT.requestPlatformFeePercentageIncrease(newFeePercentage);
        } else if(newFeePercentage > currentFee) {
            hevm.expectRevert("ZangNFTCommissions: _lowerFeePercentage must be lower than the current platform fee percentage");
            zangNFT.decreasePlatformFeePercentage(newFeePercentage);

            hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase must be first requested");
            zangNFT.applyPlatformFeePercentageIncrease();

            zangNFT.requestPlatformFeePercentageIncrease(newFeePercentage);
            assertEq(zangNFT.newPlatformFeePercentage(), newFeePercentage);
            hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
            zangNFT.applyPlatformFeePercentageIncrease();

            hevm.warp(block.timestamp + 7 days);
            zangNFT.applyPlatformFeePercentageIncrease();
            assertEq(zangNFT.platformFeePercentage(), newFeePercentage);

            hevm.expectRevert("ZangNFTCommissions: platform fee percentage increase must be first requested");
            zangNFT.applyPlatformFeePercentageIncrease();
        } else {
            hevm.expectRevert("ZangNFTCommissions: _higherFeePercentage must be higher than the current platform fee percentage");
            zangNFT.requestPlatformFeePercentageIncrease(newFeePercentage);

            zangNFT.decreasePlatformFeePercentage(newFeePercentage);
            assertEq(zangNFT.platformFeePercentage(), newFeePercentage);
        }
    }

    function test_only_owner_can_pause() public {
        marketplace.pause();
        marketplace.unpause();

        address user = address(69);

        hevm.startPrank(user);
        hevm.expectRevert("Ownable: caller is not the owner");
        marketplace.pause();
        hevm.expectRevert("Ownable: caller is not the owner");
        marketplace.unpause();
        hevm.stopPrank();

        user = address(0);

        hevm.startPrank(user);
        hevm.expectRevert("Ownable: caller is not the owner");
        marketplace.pause();
        hevm.expectRevert("Ownable: caller is not the owner");
        marketplace.unpause();
        hevm.stopPrank();
    }

    function test_pause_and_unpause() public {
        marketplace.pause();
        hevm.expectRevert("Pausable: paused");
        marketplace.listToken(0,0,0);
        hevm.expectRevert("Pausable: paused");
        marketplace.editListingAmount(0,0,0,0);
        hevm.expectRevert("Pausable: paused");
        marketplace.editListing(0,0,0,0,0);
        hevm.expectRevert("Pausable: paused");
        marketplace.editListingPrice(0,0,0);
        hevm.expectRevert("Pausable: paused");
        marketplace.delistToken(0,0);
        hevm.expectRevert("Pausable: paused");
        marketplace.buyToken(0,0,0);

        marketplace.unpause();

        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.listToken(0,0,0);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListingAmount(0,0,0,0);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListing(0,0,0,0,0);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.editListingPrice(0,0,0);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.delistToken(0,0);
        hevm.expectRevert("Marketplace: token does not exist");
        marketplace.buyToken(0,0,0);
    }

}