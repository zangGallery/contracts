// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "ds-test/test.sol";

import "./ZangNFT.sol";
import "./Marketplace.sol";

contract ZangNFTtest is DSTest {
    ZangNFT zangnft;
    Marketplace marketplace;
    struct Listing {
        uint256 price;
        address seller;
        uint256 amount;
    }

    function setUp() public {
        zangnft = new ZangNFT();
        IZangNFT izang = IZangNFT(address(zangnft));
        marketplace = new Marketplace(izang, address(this));
    }
    function test_mint(string memory uri, string memory title, string memory description, uint amount) public {
        uint preBalance = zangnft.balanceOf(address(this), 1);
        uint id = zangnft.mint(uri, title, description, amount, 1000, address(0x1), "");
        uint postBalance = zangnft.balanceOf(address(this), id);
        assertEq(preBalance + amount, postBalance);
        //assertEq(zangnft.lastTokenId(), id);
        //address author = zangnft.authorOf(id);
        //assertEq(author, address(this));
        //string memory textURI = zangnft.textURI(id);
        //assertEq(textURI, uri);
    }

    function testFail_exists_token_without_mints(uint tokenId) public {
        assertTrue(zangnft.exists(tokenId));
    }

    function test_listing() public {
        uint numTokens = 10;
        uint id = zangnft.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, numTokens);
        (uint256 price, address seller, uint256 amount) = marketplace.listings(id, 0);
        assertEq(price, 100);
        assertEq(seller, address(this));
        assertEq(amount, numTokens);
    }

    function testFail_listing_non_existent_token() public {
        marketplace.listToken(0, 100, 10);
    }

    function testFail_listing_without_approval() public {
        uint id = zangnft.mint("text", "title", "description", 10, 1000, address(0x1), "");
        marketplace.listToken(id, 100, 10);
    }

    function testFail_listing_more_than_owned(uint numTokens, uint excess) public {
        uint id = zangnft.mint("text", "title", "description", numTokens, 1000, address(0x1), "");
        zangnft.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(id, 100, numTokens + 1 + excess);
    }


}