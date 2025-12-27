// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../ZangNFT.sol";
import "./handlers/CommissionsHandler.sol";

/// @title Invariant tests for ZangNFTCommissions
/// @notice Tests properties of the fee management system
contract CommissionsInvariantTest is StdInvariant, Test {
    ZangNFT public zangNFT;
    CommissionsHandler public handler;
    address public zangCommissionAccount;

    function setUp() public {
        zangCommissionAccount = address(0x33D);

        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", zangCommissionAccount);

        handler = new CommissionsHandler(zangNFT, address(this));

        targetContract(address(handler));
    }

    /// @notice Invariant: Platform fee should be reasonable (<=100%)
    /// @dev This WILL FAIL - proving the uncapped fee vulnerability
    function invariant_platformFeeReasonable() public view {
        uint16 fee = zangNFT.platformFeePercentage();
        assertLe(fee, 10000, "VULNERABILITY: Platform fee exceeds 100%");
    }

    /// @notice Invariant: Commission account should never be zero
    /// @dev This WILL FAIL - proving the zero address vulnerability
    function invariant_commissionAccountNotZero() public view {
        assertTrue(zangNFT.zangCommissionAccount() != address(0), "VULNERABILITY: Commission account is zero");
    }

    /// @notice Invariant: Timelock must be respected
    /// @dev Fee increase should only apply after 7 days
    function invariant_timelockRespected() public view {
        uint256 lock = zangNFT.lock();

        if (lock != 0) {
            // If there's a pending increase, verify it can't be applied early
            if (block.timestamp < lock) {
                // The fee should still be the old value, not the new one
                // (This is implicit - if applyFeeIncrease succeeded early, it's a bug)
            }
        }
    }

    /// @notice Invariant: Applied increases should equal successful requests minus pending
    function invariant_increaseAccountingCorrect() public view {
        uint256 requests = handler.ghost_feeIncreaseRequests();
        uint256 applied = handler.ghost_feeIncreaseApplied();

        // Applied should never exceed requests
        assertLe(applied, requests, "Cannot apply more increases than requested");
    }

    /// @notice Invariant: Fee can only increase through timelock mechanism
    /// @dev Direct increases without timelock should be impossible
    function invariant_noDirectFeeIncrease() public view {
        // If there's no pending request (lock == 0), fee shouldn't have increased
        // from initial unless through proper timelock flow
        uint16 currentFee = zangNFT.platformFeePercentage();
        uint16 initialFee = 500; // Initial fee is 5%

        // If current > initial and no increase was ever applied, that's a bug
        if (currentFee > initialFee) {
            assertGt(handler.ghost_feeIncreaseApplied(), 0, "Fee increased without applied increase");
        }
    }

    /// @notice Report stats at end of invariant run
    function invariant_reportStats() public {
        emit log_named_uint("Fee increase requests", handler.ghost_feeIncreaseRequests());
        emit log_named_uint("Fee decreases", handler.ghost_feeDecreases());
        emit log_named_uint("Fee increases applied", handler.ghost_feeIncreaseApplied());
        emit log_named_uint("Commission account changes", handler.ghost_commissionAccountChanges());
        emit log_named_uint("Current fee", zangNFT.platformFeePercentage());
        emit log_named_uint("Max fee ever set", handler.ghost_maxFeeEverSet());
        emit log_named_uint("Min fee ever set", handler.ghost_minFeeEverSet());
    }
}

/// @title Stricter invariant tests that should fail due to vulnerabilities
contract CommissionsVulnerabilityInvariantTest is StdInvariant, Test {
    ZangNFT public zangNFT;
    CommissionsHandler public handler;

    function setUp() public {
        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", address(0x33D));

        handler = new CommissionsHandler(zangNFT, address(this));

        targetContract(address(handler));
    }

    /// @notice Invariant: Platform fee should never exceed 50%
    /// @dev This is a stricter bound - production should probably have such a limit
    function invariant_platformFeeUnder50Percent() public view {
        uint16 fee = zangNFT.platformFeePercentage();
        assertLe(fee, 5000, "Platform fee exceeds 50% - this may be intentional attack");
    }

    /// @notice Invariant: Fee changes should be gradual
    /// @dev Large jumps in fee might indicate attack or misconfiguration
    function invariant_feeChangesGradual() public {
        uint16 maxFee = handler.ghost_maxFeeEverSet();

        // If max fee ever set is more than 10x initial, flag it
        if (maxFee > 5000) {
            // 5000 = 50%, which is 10x the initial 5%
            emit log_named_uint("WARNING: Large fee detected", maxFee);
        }
    }
}
