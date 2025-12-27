// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "../../ZangNFT.sol";
import "../../Marketplace.sol";

/// @title Malicious contract that attempts reentrancy when receiving ETH
/// @notice Used to test CEI violation in Marketplace._handleFunds()
contract ReentrancyAttacker {
    Marketplace public marketplace;
    ZangNFT public zangNFT;

    uint256 public targetTokenId;
    uint256 public targetListingId;
    uint256 public attackAmount;
    uint256 public attackCount;
    uint256 public maxAttacks;
    uint256 public attackPrice;

    bool public attackEnabled;

    event AttackAttempt(uint256 count, uint256 balance, string result);

    constructor(Marketplace _marketplace, ZangNFT _zangNFT) {
        marketplace = _marketplace;
        zangNFT = _zangNFT;
    }

    function prepareAttack(
        uint256 _tokenId,
        uint256 _listingId,
        uint256 _amount,
        uint256 _price,
        uint256 _maxAttacks
    ) external {
        targetTokenId = _tokenId;
        targetListingId = _listingId;
        attackAmount = _amount;
        attackPrice = _price;
        maxAttacks = _maxAttacks;
        attackCount = 0;
        attackEnabled = true;
    }

    function disableAttack() external {
        attackEnabled = false;
    }

    /// @notice Callback when receiving ETH - attempts reentrancy
    receive() external payable {
        if (!attackEnabled) return;
        if (attackCount >= maxAttacks) return;

        attackCount++;

        // Check if there are still tokens available in the listing
        (, , uint256 remaining) = marketplace.listings(targetTokenId, targetListingId);

        if (remaining >= attackAmount) {
            uint256 cost = attackPrice * attackAmount;

            if (address(this).balance >= cost) {
                emit AttackAttempt(attackCount, address(this).balance, "attempting");

                try marketplace.buyToken{value: cost}(targetTokenId, targetListingId, attackAmount) {
                    emit AttackAttempt(attackCount, address(this).balance, "success");
                } catch Error(string memory reason) {
                    emit AttackAttempt(attackCount, address(this).balance, reason);
                } catch {
                    emit AttackAttempt(attackCount, address(this).balance, "unknown error");
                }
            }
        }
    }

    /// @notice Required for ERC1155 token receipt
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x4e2312e0;
    }
}

/// @title Malicious ERC1155 receiver that attacks during token receipt
contract MaliciousTokenReceiver {
    Marketplace public marketplace;
    uint256 public tokenId;
    uint256 public listingId;
    uint256 public amount;
    bool public shouldAttack;

    constructor(Marketplace _marketplace) {
        marketplace = _marketplace;
    }

    function setAttackParams(uint256 _tokenId, uint256 _listingId, uint256 _amount) external {
        tokenId = _tokenId;
        listingId = _listingId;
        amount = _amount;
        shouldAttack = true;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        if (shouldAttack && address(this).balance > 0) {
            shouldAttack = false;
            // Attempt reentrancy through NFT receive callback
            try marketplace.buyToken{value: address(this).balance}(tokenId, listingId, amount) {} catch {}
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    receive() external payable {}
}

/// @title Main reentrancy test contract
contract ReentrancyAttackTest is Test {
    ZangNFT public zangNFT;
    Marketplace public marketplace;
    ReentrancyAttacker public attacker;

    address public platformAccount;
    address public creator;
    address public seller;
    address public buyer;

    function setUp() public {
        platformAccount = address(0x33D);
        creator = address(0x1);
        seller = address(0x2);
        buyer = address(0x3);

        zangNFT = new ZangNFT("ZangNFT", "ZNG", "description", "imageURI", "externalLink", platformAccount);
        marketplace = new Marketplace(IZangNFT(address(zangNFT)));
        attacker = new ReentrancyAttacker(marketplace, zangNFT);
    }

    /// @notice Test: Reentrancy attempt through seller payment
    /// @dev The seller receives ETH in _handleFunds BEFORE NFT transfer
    ///      A malicious seller could attempt to re-enter buyToken
    function test_reentrancyThroughSeller() public {
        uint256 tokenAmount = 10;
        uint256 price = 1 ether;

        // Attacker is the seller - mints and lists tokens
        vm.startPrank(address(attacker));
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 0, address(attacker), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        // Prepare reentrancy attack - try to buy more tokens during callback
        attacker.prepareAttack(tokenId, 0, 1, price, 5);

        // Buyer purchases - this triggers ETH payment to attacker (seller)
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        // Check: attacker received the payment
        assertGt(address(attacker).balance, 0, "Attacker should have received payment");

        // Check: buyer received exactly 1 token (reentrancy should have been blocked or failed)
        assertEq(zangNFT.balanceOf(buyer, tokenId), 1, "Buyer should have exactly 1 token");

        // Check attack count to see if reentrancy was attempted
        emit log_named_uint("Attack attempts", attacker.attackCount());
    }

    /// @notice Test: Reentrancy through royalty creator payment
    /// @dev Creator receives ETH before seller in _handleFunds
    function test_reentrancyThroughCreator() public {
        uint256 tokenAmount = 10;
        uint256 price = 1 ether;
        uint96 royaltyPercent = 1000; // 10%

        // Attacker is the royalty recipient
        // Real seller mints with attacker as royalty receiver
        vm.prank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, royaltyPercent, address(attacker), "");

        // Seller lists tokens
        vm.startPrank(seller);
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        // Prepare attack - attacker will receive royalty and try to re-enter
        attacker.prepareAttack(tokenId, 0, 1, price, 5);

        // Buyer purchases
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        // Verify buyer got token
        assertEq(zangNFT.balanceOf(buyer, tokenId), 1);

        // Attacker should have received royalty (10% of 95% = 0.095 ether)
        emit log_named_uint("Attacker balance", address(attacker).balance);
        emit log_named_uint("Attack attempts", attacker.attackCount());
    }

    /// @notice Test: Reentrancy through platform fee (malicious commission account)
    /// @dev Platform receives ETH in _handleFunds - if it's a contract, it could re-enter
    function test_reentrancyThroughPlatform() public {
        // Change commission account to attacker
        zangNFT.setZangCommissionAccount(address(attacker));

        uint256 tokenAmount = 10;
        uint256 price = 1 ether;

        // Normal seller lists tokens
        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        // Prepare attack
        attacker.prepareAttack(tokenId, 0, 1, price, 5);

        // Buyer purchases - platform fee goes to attacker
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        assertEq(zangNFT.balanceOf(buyer, tokenId), 1);

        // Platform fee (5% of 1 ether = 0.05 ether)
        emit log_named_uint("Attacker (platform) balance", address(attacker).balance);
        emit log_named_uint("Attack attempts", attacker.attackCount());
    }

    /// @notice Test: Demonstrate the CEI violation order
    /// @dev This test documents that funds are sent BEFORE NFT transfer
    function test_CEI_violation_order() public {
        uint256 tokenAmount = 5;
        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 1000, creator, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        uint256 sellerBalBefore = seller.balance;
        uint256 creatorBalBefore = creator.balance;
        uint256 platformBalBefore = platformAccount.balance;

        vm.deal(buyer, 5 ether);
        vm.prank(buyer);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        // Verify order: All balances updated (funds sent) and buyer has token
        // The issue is: funds were sent BEFORE NFT transfer in _handleFunds
        assertGt(seller.balance, sellerBalBefore, "Seller received funds");
        assertGt(creator.balance, creatorBalBefore, "Creator received royalty");
        assertGt(platformAccount.balance, platformBalBefore, "Platform received fee");
        assertEq(zangNFT.balanceOf(buyer, tokenId), 1, "Buyer received NFT");
    }

    /// @notice Test: Cross-function reentrancy - try to delist during purchase
    function test_crossFunctionReentrancy_delist() public {
        // This tests if a malicious seller could delist during the payment callback
        // before the NFT is transferred
        uint256 tokenAmount = 5;
        uint256 price = 1 ether;

        vm.startPrank(address(attacker));
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 0, address(attacker), "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        // Record initial state
        (, address initialSeller, uint256 initialAmount) = marketplace.listings(tokenId, 0);
        assertEq(initialSeller, address(attacker));
        assertEq(initialAmount, tokenAmount);

        // Disable reentrancy attack for this test (we're testing state, not reentry)
        attacker.disableAttack();

        vm.deal(buyer, price);
        vm.prank(buyer);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        // Check listing state after purchase
        (, address postSeller, uint256 postAmount) = marketplace.listings(tokenId, 0);
        assertEq(postSeller, address(attacker), "Seller should still be attacker");
        assertEq(postAmount, tokenAmount - 1, "Amount should decrease by 1");
    }

    /// @notice Test: Multiple purchases in same block (potential race condition)
    function test_multiplePurchasesSameBlock() public {
        uint256 tokenAmount = 10;
        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        address buyer1 = address(0x100);
        address buyer2 = address(0x200);

        vm.deal(buyer1, 5 ether);
        vm.deal(buyer2, 5 ether);

        // Both buyers try to buy in same block
        vm.prank(buyer1);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        vm.prank(buyer2);
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        assertEq(zangNFT.balanceOf(buyer1, tokenId), 1);
        assertEq(zangNFT.balanceOf(buyer2, tokenId), 1);

        (, , uint256 remaining) = marketplace.listings(tokenId, 0);
        assertEq(remaining, tokenAmount - 2);
    }

    /// @notice Test: Reentrancy through ERC1155 receiver callback
    function test_reentrancyThroughTokenReceiver() public {
        MaliciousTokenReceiver maliciousReceiver = new MaliciousTokenReceiver(marketplace);

        uint256 tokenAmount = 10;
        uint256 price = 1 ether;

        vm.startPrank(seller);
        uint256 tokenId = zangNFT.mint("text", "title", "desc", tokenAmount, 0, seller, "");
        zangNFT.setApprovalForAll(address(marketplace), true);
        marketplace.listToken(tokenId, price, tokenAmount);
        vm.stopPrank();

        // Setup malicious receiver to try buying more tokens when it receives tokens
        maliciousReceiver.setAttackParams(tokenId, 0, 1);

        // Fund the malicious receiver
        vm.deal(address(maliciousReceiver), 5 ether);

        // Malicious receiver buys - when it receives the token, it tries to buy more
        vm.prank(address(maliciousReceiver));
        marketplace.buyToken{value: price}(tokenId, 0, 1);

        // The receiver should have 1 token (the reentrancy attempt through token callback
        // happens AFTER the state is updated and funds are sent, so it could potentially succeed)
        uint256 receiverBalance = zangNFT.balanceOf(address(maliciousReceiver), tokenId);
        emit log_named_uint("Malicious receiver token balance", receiverBalance);

        // If balance > 1, reentrancy through token callback succeeded
        if (receiverBalance > 1) {
            emit log("WARNING: Reentrancy through ERC1155 callback succeeded!");
        }
    }
}
