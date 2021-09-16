pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Testing.sol";

contract TestingTest is DSTest {
    Testing testing;

    function setUp() public {
        testing = new Testing();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
