// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {VectolithRegistry} from "../src/VectolithRegistry.sol";
import {VectolithMarketplaceV2} from "../src/VectolithMarketplaceV2.sol";
import {VectolithOriginals} from "../src/VectolithOriginals.sol";

contract NonReceiverMarketplaceBuyer {
    function buy(VectolithMarketplaceV2 market, uint256 listingId) external payable {
        market.buy{value: msg.value}(listingId);
    }
}

contract VectolithMarketplaceV2Test is Test {
    VectolithRegistry internal registry;
    VectolithMarketplaceV2 internal market;
    VectolithOriginals internal art;

    address internal admin = address(this);
    address internal artist = makeAddr("artist");
    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal treasury = makeAddr("treasury");

    uint256 internal constant LIST_PRICE = 1 ether;
    uint96 internal constant MARKET_FEE_BPS = 250;

    function setUp() public {
        registry = new VectolithRegistry(admin);
        art = new VectolithOriginals(
            "VECTOLITH Originals", "VECTOLITH", 10, 0, 0, artist, artist, treasury, 0
        );
        market = new VectolithMarketplaceV2(admin, registry, treasury, MARKET_FEE_BPS);

        vm.prank(artist);
        art.ownerMint(seller, "ipfs://piece-1");
        vm.prank(artist);
        registry.register(address(art), "VECTOLITH Originals", "Digital Art", "");

        vm.deal(buyer, 10 ether);
        vm.prank(seller);
        art.setApprovalForAll(address(market), true);
    }

    function _list() internal returns (uint256 listingId) {
        vm.prank(seller);
        listingId = market.list(address(art), 1, LIST_PRICE);
    }

    function test_100PercentRoyaltyIsCappedAfterProtocolFee() public {
        vm.prank(artist);
        art.setDefaultRoyalty(artist, 10_000);
        uint256 listingId = _list();

        vm.prank(buyer);
        market.buy{value: LIST_PRICE}(listingId);

        uint256 fee = (LIST_PRICE * MARKET_FEE_BPS) / 10_000;
        assertEq(market.credits(treasury), fee);
        assertEq(market.credits(artist), LIST_PRICE - fee);
        assertEq(market.credits(seller), 0);
        assertEq(
            market.credits(treasury) + market.credits(artist) + market.credits(seller),
            LIST_PRICE
        );
    }

    function test_RoyaltyAbovePriceIsCappedAfterProtocolFee() public {
        uint256 listingId = _list();
        vm.mockCall(
            address(art),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, 1, LIST_PRICE),
            abi.encode(artist, LIST_PRICE * 2)
        );

        vm.prank(buyer);
        market.buy{value: LIST_PRICE}(listingId);

        uint256 fee = (LIST_PRICE * MARKET_FEE_BPS) / 10_000;
        assertEq(market.credits(treasury), fee);
        assertEq(market.credits(artist), LIST_PRICE - fee);
        assertEq(market.credits(seller), 0);
    }

    function test_ZeroRoyaltyReceiverDoesNotReceiveCredit() public {
        uint256 listingId = _list();
        vm.mockCall(
            address(art),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, 1, LIST_PRICE),
            abi.encode(address(0), LIST_PRICE)
        );

        vm.prank(buyer);
        market.buy{value: LIST_PRICE}(listingId);

        uint256 fee = (LIST_PRICE * MARKET_FEE_BPS) / 10_000;
        assertEq(market.credits(address(0)), 0);
        assertEq(market.credits(treasury), fee);
        assertEq(market.credits(seller), LIST_PRICE - fee);
    }

    function test_RevertWhen_SupportsInterfaceReturnsMalformedBoolean() public {
        uint256 listingId = _list();
        vm.mockCall(
            address(art),
            abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x2a55205a)),
            hex"02"
        );

        vm.prank(buyer);
        vm.expectRevert(VectolithMarketplaceV2.InvalidInterfaceResponse.selector);
        market.buy{value: LIST_PRICE}(listingId);
    }

    function test_RevertWhen_RoyaltyInfoReturnsMalformedData() public {
        uint256 listingId = _list();
        vm.mockCall(
            address(art),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, 1, LIST_PRICE),
            hex"01"
        );

        vm.prank(buyer);
        vm.expectRevert(VectolithMarketplaceV2.RoyaltyQueryFailed.selector);
        market.buy{value: LIST_PRICE}(listingId);
    }

    function test_RevertWhen_RoyaltyInfoReverts() public {
        uint256 listingId = _list();
        vm.mockCallRevert(
            address(art),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, 1, LIST_PRICE),
            bytes("royalty unavailable")
        );

        vm.prank(buyer);
        vm.expectRevert(VectolithMarketplaceV2.RoyaltyQueryFailed.selector);
        market.buy{value: LIST_PRICE}(listingId);
    }

    function test_RevertWhen_RegistrySetterUsesZeroAddress() public {
        vm.expectRevert(VectolithMarketplaceV2.ZeroAddress.selector);
        market.setRegistry(VectolithRegistry(address(0)));
    }

    function test_RevertWhen_TreasurySetterUsesZeroAddress() public {
        vm.expectRevert(VectolithMarketplaceV2.ZeroAddress.selector);
        market.setTreasury(address(0));
    }

    function test_RevertWhen_ContractBuyerCannotReceiveNftSafely() public {
        uint256 listingId = _list();
        NonReceiverMarketplaceBuyer nonReceiver = new NonReceiverMarketplaceBuyer();
        vm.deal(address(nonReceiver), LIST_PRICE);

        vm.expectRevert();
        nonReceiver.buy{value: LIST_PRICE}(market, listingId);

        (,,,, bool active) = market.listings(listingId);
        assertTrue(active);
        assertEq(market.credits(seller), 0);
        assertEq(market.credits(treasury), 0);
    }

    function test_NormalSaleCreditsExactlyTheSalePrice() public {
        uint256 listingId = _list();

        vm.prank(buyer);
        market.buy{value: LIST_PRICE}(listingId);

        uint256 royalty = (LIST_PRICE * 750) / 10_000;
        uint256 fee = (LIST_PRICE * MARKET_FEE_BPS) / 10_000;
        assertEq(art.ownerOf(1), buyer);
        assertEq(market.credits(artist), royalty);
        assertEq(market.credits(treasury), fee);
        assertEq(market.credits(seller), LIST_PRICE - royalty - fee);
        assertEq(
            market.credits(artist) + market.credits(treasury) + market.credits(seller),
            LIST_PRICE
        );
    }
}
