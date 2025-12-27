// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Tests for ZangNFTCommissions vulnerabilities
/// @notice Demonstrates: uncapped platform fee, zero address commission, timelock edge cases
contract TimelockBypassTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    address public platformAccount;

    function setUp() public {
        platformAccount = address(0x33D);
        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", platformAccount);
        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
    }

    /// @notice VULNERABILITY: Platform fee can be set to any value > 100%
    /// @dev No validation that _higherFeePercentage <= 10000 (100%)
    function test_uncappedPlatformFee_canExceed100Percent() public {
        uint16 initialFee = zangNFT.platformFeePercentage();
        assertEq(initialFee, 500, "Initial fee should be 5%");

        // Request a fee of 20000 (200%) - THIS SHOULD NOT BE ALLOWED
        uint16 absurdFee = 20000; // 200%
        zangNFT.requestPlatformFeePercentageIncrease(absurdFee);

        assertEq(zangNFT.newPlatformFeePercentage(), absurdFee, "Absurd fee was accepted");

        // Wait for timelock
        vm.warp(block.timestamp + 7 days);

        // Apply the absurd fee
        zangNFT.applyPlatformFeePercentageIncrease();

        assertEq(zangNFT.platformFeePercentage(), absurdFee, "Platform fee is now 200%!");

        emit log("VULNERABILITY CONFIRMED: Platform fee can exceed 100%");
    }

    /// @notice VULNERABILITY: Platform fee can be set to max uint16 (655.35%)
    function test_uncappedPlatformFee_maxValue() public {
        uint16 maxFee = type(uint16).max; // 65535 = 655.35%

        zangNFT.requestPlatformFeePercentageIncrease(maxFee);
        vm.warp(block.timestamp + 7 days);
        zangNFT.applyPlatformFeePercentageIncrease();

        assertEq(zangNFT.platformFeePercentage(), maxFee);

        emit log_named_uint("Platform fee percentage (basis points)", zangNFT.platformFeePercentage());
        emit log("VULNERABILITY CONFIRMED: Platform fee can be set to 655.35%");
    }

    /// @notice VULNERABILITY: Zero address can be set as commission account
    /// @dev This will cause all purchases to fail since ETH can't be sent to address(0)
    function test_zeroAddressCommission_canBeSet() public {
        // Set commission account to zero address
        zangNFT.setZangCommissionAccount(address(0));

        assertEq(zangNFT.zangCommissionAccount(), address(0), "Commission account is zero");

        emit log("VULNERABILITY CONFIRMED: Commission account can be set to address(0)");
    }

    /// @notice VULNERABILITY IMPACT: Zero address commission burns platform fees
    /// @dev ETH sent to address(0) via .call{value} succeeds - ETH is LOST
    function test_zeroAddressCommission_burnsEth() public {
        // Setup a listing
        address seller = address(0x1);
        address buyer = address(0x2);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 10, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, 1 ether, 10);
        vm.stopPrank();

        // Set commission account to zero address
        zangNFT.setZangCommissionAccount(address(0));

        // Purchase succeeds but platform fee is sent to address(0) and BURNED
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: 1 ether}(tokenId, 0, 1);

        // Platform fee (5% of 1 ether = 0.05 ether) is now burned!
        // Check that address(0) received the fee (it's burned, but balance shows it)
        assertEq(address(0).balance, 0.05 ether, "Platform fee burned to zero address");

        emit log("VULNERABILITY IMPACT: Zero address commission BURNS platform fees (ETH lost forever)");
    }

    /// @notice VULNERABILITY IMPACT: Excessive fee causes arithmetic underflow
    /// @dev When platformFee > salePrice, remainder calculation underflows
    function test_excessiveFee_causesUnderflow() public {
        // Set platform fee to 150%
        zangNFT.requestPlatformFeePercentageIncrease(15000);
        vm.warp(block.timestamp + 7 days);
        zangNFT.applyPlatformFeePercentageIncrease();

        // Setup a listing
        address seller = address(0x1);
        address buyer = address(0x2);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 10, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, 1 ether, 1);
        vm.stopPrank();

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);

        // Platform fee = 1 ether * 15000 / 10000 = 1.5 ether
        // remainder = 1 ether - 1.5 ether = UNDERFLOW!
        // Solidity 0.8+ reverts with panic code 0x11

        vm.expectRevert(stdError.arithmeticError);
        marketplace.buyToken{value: 1 ether}(tokenId, 0, 1);

        emit log("VULNERABILITY IMPACT: Excessive fee (>100%) causes ALL purchases to fail with underflow");
    }

    /// @notice Test: Timelock edge case - requesting increase then decrease
    function test_timelockEdgeCase_decreaseDuringPending() public {
        uint16 initialFee = zangNFT.platformFeePercentage(); // 500

        // Request increase to 1000
        zangNFT.requestPlatformFeePercentageIncrease(1000);

        // Before timelock expires, decrease the fee
        zangNFT.decreasePlatformFeePercentage(300);
        assertEq(zangNFT.platformFeePercentage(), 300);

        // Wait for timelock
        vm.warp(block.timestamp + 7 days);

        // Try to apply the old increase - it should still work!
        // This could be unexpected behavior
        zangNFT.applyPlatformFeePercentageIncrease();

        // Fee jumps from 300 to 1000, bypassing any intermediate states
        assertEq(zangNFT.platformFeePercentage(), 1000);

        emit log("Edge case: Fee jumped from 300 to 1000 after decrease during pending increase");
    }

    /// @notice Test: Multiple timelock requests reset the timer
    function test_timelockReset_multipleRequests() public {
        uint256 startTime = block.timestamp;

        // First request at time 0
        zangNFT.requestPlatformFeePercentageIncrease(600);
        uint256 lock1 = zangNFT.lock();
        assertEq(lock1, startTime + 7 days);

        // Wait 3 days
        vm.warp(startTime + 3 days);

        // Second request - should reset timelock
        zangNFT.requestPlatformFeePercentageIncrease(700);
        uint256 lock2 = zangNFT.lock();
        assertEq(lock2, startTime + 3 days + 7 days, "Lock should reset to new timestamp + 7 days");

        // Try to apply at original expiry (day 7)
        vm.warp(startTime + 7 days);
        vm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
        zangNFT.applyPlatformFeePercentageIncrease();

        // Wait until new expiry (day 10)
        vm.warp(startTime + 10 days);
        zangNFT.applyPlatformFeePercentageIncrease();
        assertEq(zangNFT.platformFeePercentage(), 700);

        emit log("Confirmed: Multiple requests properly reset the timelock");
    }

    /// @notice Test: Timelock can be circumvented by owner role transfer
    /// @dev If ownership is transferred, new owner can immediately request new fee
    function test_timelockEdgeCase_ownershipTransfer() public {
        address newOwner = address(0x999);

        // Current owner requests fee increase
        zangNFT.requestPlatformFeePercentageIncrease(600);

        // Transfer ownership
        zangNFT.transferOwnership(newOwner);

        // New owner can request their own increase immediately
        vm.prank(newOwner);
        zangNFT.requestPlatformFeePercentageIncrease(1000);

        // Wait 7 days
        vm.warp(block.timestamp + 7 days);

        // New owner applies their fee
        vm.prank(newOwner);
        zangNFT.applyPlatformFeePercentageIncrease();

        assertEq(zangNFT.platformFeePercentage(), 1000);
    }

    /// @notice Test: Fee precision at boundary (exactly 100%)
    function test_fee_exactlyOneHundredPercent() public {
        zangNFT.requestPlatformFeePercentageIncrease(10000); // 100%
        vm.warp(block.timestamp + 7 days);
        zangNFT.applyPlatformFeePercentageIncrease();

        assertEq(zangNFT.platformFeePercentage(), 10000);

        // Setup a sale
        address seller = address(0x1);
        address buyer = address(0x2);

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 10, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, 1 ether, 1);
        vm.stopPrank();

        uint256 platformBalBefore = platformAccount.balance;
        uint256 sellerBalBefore = seller.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: 1 ether}(tokenId, 0, 1);

        // At 100% fee, platform gets everything, seller gets nothing
        assertEq(platformAccount.balance - platformBalBefore, 1 ether, "Platform should get 100%");
        assertEq(seller.balance - sellerBalBefore, 0, "Seller should get 0");

        emit log("At 100% fee: Platform takes entire sale, seller gets nothing");
    }

    /// @notice Fuzz test: Any fee above current can be requested (no upper bound)
    function testFuzz_anyFeeAboveCurrentCanBeRequested(uint16 newFee) public {
        uint16 currentFee = zangNFT.platformFeePercentage();
        vm.assume(newFee > currentFee);

        // This should never revert - proving there's no upper bound validation
        zangNFT.requestPlatformFeePercentageIncrease(newFee);
        assertEq(zangNFT.newPlatformFeePercentage(), newFee);
    }

    /// @notice Fuzz test: Any address can be set as commission account
    function testFuzz_anyAddressCanBeCommissionAccount(address newAccount) public {
        // This should never revert - even address(0)
        zangNFT.setZangCommissionAccount(newAccount);
        assertEq(zangNFT.zangCommissionAccount(), newAccount);
    }
}
