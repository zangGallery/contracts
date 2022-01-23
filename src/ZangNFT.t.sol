// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "ds-test/test.sol";

import "./ZangNFT.sol";
import "./Marketplace.sol";

interface Hevm {
    function prank(address) external;
    function expectRevert(bytes calldata) external;
    function deal(address, uint256) external;
    function startPrank(address) external;
    function stopPrank() external;
}

contract ZangNFTtest is DSTest {
    ZangNFT zangnft;
    Marketplace marketplace;
    Hevm constant hevm = Hevm(HEVM_ADDRESS);
    address zangCommissionAccount = address(0x33D);
    struct Listing {
        uint256 price;
        address seller;
        uint256 amount;
    }

    function setUp() public {
        zangnft = new ZangNFT("ZangNFT", "ZNG");
        IZangNFT izang = IZangNFT(address(zangnft));
        marketplace = new Marketplace(izang, zangCommissionAccount);
    }
    function test_mint(string memory uri, string memory title, string memory description, uint amount) public {
        address user = address(69);
        hevm.startPrank(user);
        uint preBalance = zangnft.balanceOf(user, 1);
        uint id = zangnft.mint(uri, title, description, amount, 1000, address(0x1), "");
        uint postBalance = zangnft.balanceOf(user, id);
        assertEq(preBalance + amount, postBalance);
        assertEq(zangnft.lastTokenId(), id);
        address author = zangnft.authorOf(id);
        assertEq(author, user);
        string memory textURI = zangnft.textURI(id);
        assertEq(textURI, uri);
        hevm.stopPrank();
    }

    function testFail_exists_token_without_mints(uint tokenId) public {
        assertTrue(zangnft.exists(tokenId));
    }

    function test_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint numTokens = 10;
        uint id = zangnft.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, numTokens);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(id, 0);
        assertEq(price, 100);
        assertEq(seller, user);
        assertEq(amount, numTokens);
        hevm.stopPrank();
    }

    function test_listing_non_existent_token() public {
        hevm.expectRevert("Token does not exist");
        marketplace.listToken(0, 100, 10);
    }

    function test_listing_more_than_owned() public {
        hevm.startPrank(address(69));
        uint numTokens = 10;
        uint id = zangnft.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Not enough tokens to list");
        marketplace.listToken(id, 100, numTokens + 1);
        hevm.stopPrank();
    }

    function test_listing_without_approval() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        hevm.expectRevert("Marketplace contract is not approved");
        marketplace.listToken(id, 100, 10);
        hevm.stopPrank();
    }

    function test_listing_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Amount must be greater than 0");
        marketplace.listToken(id, 100, 0);
        hevm.stopPrank();
    }

    function test_listing_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        hevm.expectRevert("Price must be greater than 0");
        marketplace.listToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_list_two_tokens() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id1 = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        uint id2 = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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

        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        assertEq(id, 1);
        zangnft.setApprovalForAll(address(marketplace), true);
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
        hevm.expectRevert("Listing ID out of bounds");
        marketplace.delistToken(1, 0);
    }

    function test_delist_a_delisted_listing() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        marketplace.delistToken(id, 0);
        hevm.expectRevert("Cannot interact with a delisted listing");
        marketplace.delistToken(id, 0);
        hevm.stopPrank();
    }

    function test_delist_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangnft.mint("texturi", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        zangnft.safeTransferFrom(user, address(1559), id, 10, "");
        hevm.stopPrank();
        hevm.prank(address(1559));
        hevm.expectRevert("Only the seller can delist");
        marketplace.delistToken(id, 0);
    }

    function test_buy_all_listed_token() public {
        address minter = address(1);
        uint amount = 10;
        hevm.startPrank(minter);
        uint id = zangnft.mint("text", "title", "description", amount, 1000, address(0x1), "");
        assertEq(zangnft.balanceOf(minter, id), amount);
        zangnft.setApprovalForAll(address(marketplace), true);
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

        uint balance = zangnft.balanceOf(buyer, id);
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
        uint id = zangnft.mint("text", "title", "description", amount, 1000, address(0x1), "");
        zangnft.safeTransferFrom(minter, receiver, id, amount, "");
        hevm.stopPrank();

        hevm.startPrank(receiver);
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, amount);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 10 ether);
        marketplace.buyToken{value: 10 ether}(id, 0, 10);
        hevm.stopPrank();

        assertEq(buyer.balance, 0);
        assertEq(zangCommissionAccount.balance, 0.5 ether);
        assertEq(minter.balance, 1 ether);
        assertEq(receiver.balance, 8.5 ether);
    }

    function test_buy_nonexistent_listing() public {
        hevm.expectRevert("Listing index out of bounds");
        marketplace.buyToken(1, 0, 10);
    }

    function test_buy_delisted_listing() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        marketplace.delistToken(id, 0);
        hevm.expectRevert("Cannot interact with a delisted listing");
        marketplace.buyToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_buy_own_listing() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        hevm.expectRevert("Cannot buy from yourself");
        marketplace.buyToken(id, 0, 10);
        hevm.stopPrank();
    }

    function test_buy_more_than_listed() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        hevm.expectRevert("Not enough tokens to buy");
        hevm.stopPrank();
        hevm.prank(address(1));
        marketplace.buyToken(id, 0, 11);
    }

    function test_seller_does_not_have_enough_tokens_anymore() public {
        address seller = address(1);
        address receiver = address(2);
        address buyer = address(3);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, 10);
        zangnft.safeTransferFrom(seller, receiver, id, 5, "");
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 10 ether);
        hevm.expectRevert("Seller does not have enough tokens anymore");
        marketplace.buyToken{value: 10 ether}(id, 0, 10);
        hevm.stopPrank();
    }

    function test_price_does_not_match() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 5 ether, 10);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        hevm.expectRevert("Price does not match");
        marketplace.buyToken{value: 1 ether}(id, 0, 10);
        hevm.stopPrank();
    }

    function test_frontrun_buy_on_different_listing() public {
        address seller = address(1);
        address buyer1 = address(2);
        address buyer2 = address(3);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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

        assertEq(zangnft.balanceOf(buyer1, id), 5);
        assertEq(zangnft.balanceOf(buyer2, id), 5);
    }

    function test_edit_listing() public {
        address seller = address(1);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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
        hevm.expectRevert("Token does not exist");
        marketplace.editListing(1, 0, 2 ether, 10, 5);
    }

    function test_edit_listing_more_than_owned() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Not enough tokens to list");
        marketplace.editListing(id, 0, 2 ether, 11, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Amount must be greater than 0");
        marketplace.editListing(id, 0, 2 ether, 0, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Price must be greater than 0");
        marketplace.editListing(id, 0, 0 ether, 10, 5);
        hevm.stopPrank();
    }

    function test_edit_nonexistent_listing() public {
        hevm.startPrank(address(69));
        zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        hevm.expectRevert("Listing does not exist");
        marketplace.editListing(1, 0, 2 ether, 10, 5);
        hevm.stopPrank();
    }

    function test_edit_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        zangnft.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.prank(address(1));
        hevm.expectRevert("Only seller can edit listing");
        marketplace.editListing(id, 0, 2 ether, 5, 5);
    }

    function test_edit_listing_with_wrong_expected_amount_because_of_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        marketplace.buyToken{value: 1 ether}(id, 0, 1);
        hevm.stopPrank();

        hevm.startPrank(seller);
        hevm.expectRevert("Expected amount does not match");
        marketplace.editListing(id, 0, 2 ether, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_price() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        marketplace.editListingPrice(id, 0, 2 ether);

        (uint price, address seller, uint amount) = marketplace.listings(id, 0);
        assertEq(price, 2 ether);
        assertEq(seller, user);
        assertEq(amount, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_nonexistent_token() public {
        hevm.expectRevert("Token does not exist");
        marketplace.editListingPrice(1, 0, 2 ether);
    }

    function test_edit_listing_price_with_price_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Price must be greater than 0");
        marketplace.editListingPrice(id, 0, 0 ether);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_nonexistent_listing() public {
        hevm.startPrank(address(69));
        zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        hevm.expectRevert("Listing does not exist");
        marketplace.editListingPrice(1, 0, 2 ether);
        hevm.stopPrank();
    }

    function test_edit_listing_price_of_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        zangnft.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.prank(address(1));
        hevm.expectRevert("Only seller can edit listing");
        marketplace.editListingPrice(id, 0, 2 ether);
    }

    function test_edit_listing_price_with_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
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
        hevm.expectRevert("Token does not exist");
        marketplace.editListingAmount(1, 0, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_with_more_than_owned() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Not enough tokens to list");
        marketplace.editListingAmount(id, 0, 11, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_with_amount_zero() public {
        hevm.startPrank(address(69));
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.expectRevert("Amount must be greater than 0");
        marketplace.editListingAmount(id, 0, 0, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_of_non_existent_listing() public {
        hevm.startPrank(address(69));
        zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        hevm.expectRevert("Listing does not exist");
        marketplace.editListingAmount(1, 0, 5, 5);
        hevm.stopPrank();
    }

    function test_edit_listing_amount_of_someone_else_listing() public {
        address user = address(69);
        hevm.startPrank(user);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        zangnft.safeTransferFrom(user, address(1), id, 5, "");
        hevm.stopPrank();

        hevm.prank(address(1));
        hevm.expectRevert("Only seller can edit listing");
        marketplace.editListingAmount(id, 0, 5, 5);
    }

    function test_edit_listing_amount_with_wrong_expected_amount_because_of_buyer() public {
        address seller = address(1);
        address buyer = address(2);

        hevm.startPrank(seller);
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 1 ether, 5);
        hevm.stopPrank();

        hevm.startPrank(buyer);
        hevm.deal(buyer, 1 ether);
        marketplace.buyToken{value: 1 ether}(id, 0, 1);
        hevm.stopPrank();

        hevm.startPrank(seller);
        hevm.expectRevert("Expected amount does not match");
        marketplace.editListingAmount(id, 0, 5, 5);
        hevm.stopPrank();
    }
}