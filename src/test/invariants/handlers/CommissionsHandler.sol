// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../../ZangNFT.sol";

/// @title Handler for ZangNFTCommissions invariant testing
/// @notice Provides bounded operations for testing fee management
contract CommissionsHandler is Test {
    ZangNFT public zangNFT;
    address public owner;

    // Ghost variables
    uint256 public ghost_feeIncreaseRequests;
    uint256 public ghost_feeDecreases;
    uint256 public ghost_feeIncreaseApplied;
    uint256 public ghost_commissionAccountChanges;

    // Track fee history
    uint16[] public feeHistory;
    uint16 public ghost_maxFeeEverSet;
    uint16 public ghost_minFeeEverSet;

    // Track timing
    uint256 public ghost_lastRequestTime;
    uint256 public ghost_lastApplyTime;

    constructor(ZangNFT _zangNFT, address _owner) {
        zangNFT = _zangNFT;
        owner = _owner;
        ghost_minFeeEverSet = type(uint16).max;
        feeHistory.push(zangNFT.platformFeePercentage());
    }

    /// @notice Decrease platform fee (immediate)
    function decreaseFee(uint16 newFee) external {
        vm.prank(owner);
        try zangNFT.decreasePlatformFeePercentage(newFee) {
            ghost_feeDecreases++;
            feeHistory.push(newFee);

            if (newFee < ghost_minFeeEverSet) {
                ghost_minFeeEverSet = newFee;
            }
        } catch {}
    }

    /// @notice Request fee increase (requires timelock)
    function requestFeeIncrease(uint16 newFee) external {
        vm.prank(owner);
        try zangNFT.requestPlatformFeePercentageIncrease(newFee) {
            ghost_feeIncreaseRequests++;
            ghost_lastRequestTime = block.timestamp;
        } catch {}
    }

    /// @notice Apply pending fee increase
    function applyFeeIncrease() external {
        vm.prank(owner);
        try zangNFT.applyPlatformFeePercentageIncrease() {
            ghost_feeIncreaseApplied++;
            ghost_lastApplyTime = block.timestamp;

            uint16 newFee = zangNFT.platformFeePercentage();
            feeHistory.push(newFee);

            if (newFee > ghost_maxFeeEverSet) {
                ghost_maxFeeEverSet = newFee;
            }
        } catch {}
    }

    /// @notice Change commission account
    function setCommissionAccount(address newAccount) external {
        vm.prank(owner);
        try zangNFT.setZangCommissionAccount(newAccount) {
            ghost_commissionAccountChanges++;
        } catch {}
    }

    /// @notice Warp time forward
    function warpTime(uint256 secondsToWarp) external {
        secondsToWarp = bound(secondsToWarp, 0, 30 days);
        vm.warp(block.timestamp + secondsToWarp);
    }

    /// @notice Get fee history length
    function feeHistoryLength() external view returns (uint256) {
        return feeHistory.length;
    }
}
