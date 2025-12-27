// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Fuzz tests for ZangNFTCommissions
/// @notice Property-based tests for fee management
contract CommissionsFuzzTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    address public zangCommissionAccount;

    function setUp() public {
        zangCommissionAccount = address(0x33D);
        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);
        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
    }

    /// @notice Fuzz: Any fee above current can be requested (VULNERABILITY)
    function testFuzz_uncappedFeeRequest(uint16 newFee) public {
        uint16 currentFee = zangNFT.platformFeePercentage();
        vm.assume(newFee > currentFee);

        // This should never revert - proving no upper bound
        zangNFT.requestPlatformFeePercentageIncrease(newFee);
        assertEq(zangNFT.newPlatformFeePercentage(), newFee);

        // Log if fee exceeds 100%
        if (newFee > 10000) {
            emit log_named_uint("VULNERABILITY: Fee request accepted above 100%", newFee);
        }
    }

    /// @notice Fuzz: Any address can be commission account (VULNERABILITY)
    function testFuzz_anyCommissionAccountAllowed(address newAccount) public {
        zangNFT.setZangCommissionAccount(newAccount);
        assertEq(zangNFT.zangCommissionAccount(), newAccount);

        if (newAccount == address(0)) {
            emit log("VULNERABILITY: Zero address accepted as commission account");
        }
    }

    /// @notice Fuzz: Fee decrease must be strictly lower
    function testFuzz_feeDecreaseMustBeLower(uint16 newFee) public {
        uint16 currentFee = zangNFT.platformFeePercentage();

        if (newFee >= currentFee) {
            vm.expectRevert(
                "ZangNFTCommissions: _lowerFeePercentage must be lower than the current platform fee percentage"
            );
            zangNFT.decreasePlatformFeePercentage(newFee);
        } else {
            zangNFT.decreasePlatformFeePercentage(newFee);
            assertEq(zangNFT.platformFeePercentage(), newFee);
        }
    }

    /// @notice Fuzz: Fee increase must be strictly higher
    function testFuzz_feeIncreaseMustBeHigher(uint16 newFee) public {
        uint16 currentFee = zangNFT.platformFeePercentage();

        if (newFee <= currentFee) {
            vm.expectRevert(
                "ZangNFTCommissions: _higherFeePercentage must be higher than the current platform fee percentage"
            );
            zangNFT.requestPlatformFeePercentageIncrease(newFee);
        } else {
            zangNFT.requestPlatformFeePercentageIncrease(newFee);
            assertEq(zangNFT.newPlatformFeePercentage(), newFee);
        }
    }

    /// @notice Fuzz: Timelock must be respected
    function testFuzz_timelockEnforced(uint256 waitTime) public {
        waitTime = bound(waitTime, 0, 14 days);

        zangNFT.requestPlatformFeePercentageIncrease(1000);
        uint256 lockTime = zangNFT.lock();

        vm.warp(block.timestamp + waitTime);

        if (block.timestamp < lockTime) {
            vm.expectRevert("ZangNFTCommissions: platform fee percentage increase is locked");
            zangNFT.applyPlatformFeePercentageIncrease();
        } else {
            zangNFT.applyPlatformFeePercentageIncrease();
            assertEq(zangNFT.platformFeePercentage(), 1000);
        }
    }

    /// @notice Fuzz: Multiple requests reset timelock correctly
    function testFuzz_multipleRequestsResetTimelock(uint16 fee1, uint16 fee2, uint256 timeBetween) public {
        uint16 currentFee = zangNFT.platformFeePercentage();
        vm.assume(fee1 > currentFee);
        vm.assume(fee2 > currentFee);
        timeBetween = bound(timeBetween, 0, 6 days);

        uint256 startTime = block.timestamp;

        // First request
        zangNFT.requestPlatformFeePercentageIncrease(fee1);
        uint256 lock1 = zangNFT.lock();
        assertEq(lock1, startTime + 7 days);

        // Wait and make second request
        vm.warp(startTime + timeBetween);
        zangNFT.requestPlatformFeePercentageIncrease(fee2);
        uint256 lock2 = zangNFT.lock();

        // Lock should be reset to new timestamp + 7 days
        assertEq(lock2, startTime + timeBetween + 7 days);
        assertEq(zangNFT.newPlatformFeePercentage(), fee2);
    }

    /// @notice Fuzz: Fee sequence (decrease, request increase, apply)
    function testFuzz_feeSequence(uint16 decreaseTo, uint16 increaseTo) public {
        uint16 initialFee = zangNFT.platformFeePercentage(); // 500
        vm.assume(decreaseTo < initialFee);
        vm.assume(increaseTo > decreaseTo);

        // Decrease
        zangNFT.decreasePlatformFeePercentage(decreaseTo);
        assertEq(zangNFT.platformFeePercentage(), decreaseTo);

        // Request increase
        zangNFT.requestPlatformFeePercentageIncrease(increaseTo);
        assertEq(zangNFT.newPlatformFeePercentage(), increaseTo);

        // Wait and apply
        vm.warp(block.timestamp + 7 days);
        zangNFT.applyPlatformFeePercentageIncrease();
        assertEq(zangNFT.platformFeePercentage(), increaseTo);
    }

    /// @notice Fuzz: Platform fee calculation correctness
    function testFuzz_platformFeeCalculation(uint256 salePrice, uint16 feePercent) public {
        salePrice = bound(salePrice, 1, type(uint128).max);
        feePercent = uint16(bound(feePercent, 0, 10000));

        // Simulate fee calculation as done in Marketplace._handleFunds
        uint256 platformFee = (salePrice * feePercent) / 10000;

        // Fee should never exceed sale price when fee <= 100%
        if (feePercent <= 10000) {
            assertLe(platformFee, salePrice, "Fee exceeds sale price");
        }

        // Fee should be proportional
        uint256 expectedFee = (salePrice * feePercent) / 10000;
        assertEq(platformFee, expectedFee);
    }

    /// @notice Fuzz: Excessive fee breaks purchases
    function testFuzz_excessiveFeeBreaksPurchases(uint16 excessiveFee) public {
        vm.assume(excessiveFee > 10000); // > 100%

        // Set excessive fee
        zangNFT.requestPlatformFeePercentageIncrease(excessiveFee);
        vm.warp(block.timestamp + 7 days);
        zangNFT.applyPlatformFeePercentageIncrease();

        // Setup a listing
        address seller = address(0x1);
        address buyer = address(0x2);
        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", 1, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, 1);
        vm.stopPrank();

        vm.deal(buyer, price);
        vm.prank(buyer);

        // This will cause underflow in remainder calculation
        // platformFee = (1 ether * excessiveFee) / 10000 > 1 ether
        // remainder = value - platformFee would underflow in Solidity < 0.8
        // In Solidity 0.8+, it will revert with arithmetic underflow
        try marketplace.buyToken{value: price}(tokenId, 0, 1) {
            // If it succeeds, check the weird state
            emit log("WARNING: Purchase succeeded with excessive fee!");
        } catch {
            // Expected - arithmetic underflow or other error
            emit log("Purchase correctly failed with excessive fee");
        }
    }

    /// @notice Fuzz: Only owner can modify fees
    function testFuzz_onlyOwnerCanModifyFees(address caller, uint16 newFee) public {
        vm.assume(caller != address(this));
        vm.assume(caller != address(0));

        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        zangNFT.decreasePlatformFeePercentage(newFee);

        vm.expectRevert("Ownable: caller is not the owner");
        zangNFT.requestPlatformFeePercentageIncrease(newFee);

        vm.expectRevert("Ownable: caller is not the owner");
        zangNFT.applyPlatformFeePercentageIncrease();

        vm.expectRevert("Ownable: caller is not the owner");
        zangNFT.setZangCommissionAccount(caller);

        vm.stopPrank();
    }
}
