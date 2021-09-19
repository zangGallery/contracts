// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "ds-test/test.sol";

import "./ZangNFT.sol";

contract ZangNFTtest is DSTest {
    ZangNFT zangnft;

    function setUp() public {
        zangnft = new ZangNFT();
    }
    function test_mint(string memory uri, string memory title, string memory description, uint amount) public {
        uint preBalance = zangnft.balanceOf(address(this), 1);
        uint id = zangnft.mint(uri, title, description, amount, 1000, address(0x1), "");
        uint postBalance = zangnft.balanceOf(address(this), id);
        assertEq(preBalance + amount, postBalance);
        assertEq(zangnft.lastTokenId(), id);
        address author = zangnft.authorOf(id);
        assertEq(author, address(this));
        string memory textURI = zangnft.textURI(id);
        assertEq(textURI, uri);
    }
}