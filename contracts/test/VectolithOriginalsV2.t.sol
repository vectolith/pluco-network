// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {VectolithOriginalsV2} from "../src/VectolithOriginalsV2.sol";

contract RejectingTreasury {
    receive() external payable {
        revert("reject ether");
    }
}

contract VectolithOriginalsV2Test is Test {
    VectolithOriginalsV2 internal collection;
    address internal artist = makeAddr("artist");
    address internal buyer = makeAddr("buyer");
    address internal treasury = makeAddr("treasury");
    uint256 internal constant PRICE = 1 ether;

    function setUp() public {
        collection = new VectolithOriginalsV2(
            "VECTOLITH Originals V2",
            "VECTOLITH2",
            2,
            PRICE,
            1,
            address(this),
            artist,
            treasury,
            250
        );
        vm.deal(buyer, 10 ether);
        collection.setSaleOpen(true);
    }

    function test_MintAccruesProtocolFeeWithoutCallingTreasury() public {
        RejectingTreasury rejectingTreasury = new RejectingTreasury();
        VectolithOriginalsV2 target = new VectolithOriginalsV2(
            "VECTOLITH Originals V2",
            "VECTOLITH2",
            2,
            PRICE,
            1,
            address(this),
            artist,
            address(rejectingTreasury),
            250
        );
        target.setSaleOpen(true);

        vm.prank(buyer);
        target.mint{value: PRICE}("ipfs://piece-1");

        assertEq(target.ownerOf(1), buyer);
        assertEq(target.credits(address(rejectingTreasury)), 0.025 ether);
        assertEq(address(rejectingTreasury).balance, 0);
    }

    function test_WithdrawPaysAccruedFeeAndClearsCredit() public {
        vm.prank(buyer);
        collection.mint{value: PRICE}("ipfs://piece-1");

        uint256 beforeBalance = treasury.balance;
        vm.prank(treasury);
        collection.withdraw();

        assertEq(treasury.balance - beforeBalance, 0.025 ether);
        assertEq(collection.credits(treasury), 0);
    }

    function test_RevertWhen_TreasuryIsZeroAtConstruction() public {
        vm.expectRevert(VectolithOriginalsV2.ZeroAddress.selector);
        new VectolithOriginalsV2(
            "VECTOLITH Originals V2", "V2", 2, PRICE, 1,
            address(this), artist, address(0), 250
        );
    }

    function test_RevertWhen_TreasuryIsSetToZero() public {
        vm.expectRevert(VectolithOriginalsV2.ZeroAddress.selector);
        collection.setTreasury(address(0));
    }

    function test_RevertWhen_FeeExceedsTenPercent() public {
        vm.expectRevert(VectolithOriginalsV2.FeeTooHigh.selector);
        collection.setFeeBps(1_001);
    }

    function test_RevertWhen_MintingBeforeSaleOpens() public {
        collection.setSaleOpen(false);
        vm.prank(buyer);
        vm.expectRevert(VectolithOriginalsV2.SaleClosed.selector);
        collection.mint{value: PRICE}("ipfs://piece-1");
    }

    function test_RevertWhen_MintPriceIsIncorrect() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                VectolithOriginalsV2.WrongPrice.selector,
                PRICE,
                PRICE / 2
            )
        );
        collection.mint{value: PRICE / 2}("ipfs://piece-1");
    }

    function test_RevertWhen_WalletExceedsMintLimit() public {
        vm.startPrank(buyer);
        collection.mint{value: PRICE}("ipfs://piece-1");
        vm.expectRevert(VectolithOriginalsV2.WalletLimit.selector);
        collection.mint{value: PRICE}("ipfs://piece-2");
        vm.stopPrank();
    }

    function test_ProvenanceCanBeCommittedOnlyOnce() public {
        collection.setProvenance("sha256:artwork-manifest");
        assertEq(collection.provenance(), "sha256:artwork-manifest");
        assertTrue(collection.provenanceFrozen());

        vm.expectRevert(VectolithOriginalsV2.ProvenanceAlreadyCommitted.selector);
        collection.setProvenance("sha256:replacement");
    }

    function test_RevertWhen_EmptyProvenanceIsCommitted() public {
        vm.expectRevert(VectolithOriginalsV2.EmptyProvenance.selector);
        collection.setProvenance("");
    }

    function test_RoyaltyAndInterfaceRemainEip2981Compatible() public view {
        (address receiver, uint256 royalty) = IERC2981(address(collection)).royaltyInfo(1, PRICE);
        assertEq(receiver, artist);
        assertEq(royalty, 0.075 ether);
        assertTrue(collection.supportsInterface(type(IERC2981).interfaceId));
    }

    function test_OwnerMintRequiresNonzeroRecipientAndDoesNotChargePayment() public {
        collection.ownerMint(buyer, "ipfs://reserved");
        assertEq(collection.ownerOf(1), buyer);

        vm.expectRevert(VectolithOriginalsV2.ZeroAddress.selector);
        collection.ownerMint(address(0), "ipfs://invalid");
    }
}
