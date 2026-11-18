// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VectolithRegistry} from "./VectolithRegistry.sol";

/**
 * @title VectolithMarketplaceV2
 * @notice Hardened, separately deployed successor to the immutable V1 marketplace.
 *
 * V2 caps royalties after reserving the protocol fee, validates optional EIP-2981
 * responses, uses safe NFT delivery, and rejects zero-address admin configuration.
 * It deliberately does not alter or claim to upgrade the deployed V1 contract.
 */
contract VectolithMarketplaceV2 is Ownable, ReentrancyGuard {
    struct Listing {
        address seller;
        address collection;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    VectolithRegistry public registry;
    address public treasury;
    uint96 public feeBps;

    uint256 public listingCount;
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => uint256)) public activeListing;
    mapping(address => uint256) public credits;

    event Listed(uint256 indexed listingId, address indexed collection, uint256 indexed tokenId, address seller, uint256 price);
    event PriceUpdated(uint256 indexed listingId, uint256 price);
    event Delisted(uint256 indexed listingId);
    event Sold(uint256 indexed listingId, address indexed buyer, uint256 price, uint256 royalty, uint256 fee);
    event Withdrawn(address indexed account, uint256 amount);
    event RegistrySet(address registry);
    event TreasurySet(address treasury);
    event FeeSet(uint96 feeBps);

    error ZeroAddress();
    error NotRegistered();
    error NotOwnerOfToken();
    error NotApproved();
    error BadPrice();
    error NotSeller();
    error Inactive();
    error WrongValue(uint256 expected);
    error TransferFailed();
    error FeeTooHigh();
    error NothingToWithdraw();
    error InvalidInterfaceResponse();
    error RoyaltyQueryFailed();

    constructor(address owner_, VectolithRegistry registry_, address treasury_, uint96 feeBps_) Ownable(owner_) {
        if (address(registry_) == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (feeBps_ > 500) revert FeeTooHigh();
        registry = registry_;
        treasury = treasury_;
        feeBps = feeBps_;
    }

    function list(address collection, uint256 tokenId, uint256 price) external returns (uint256 listingId) {
        if (!registry.isActive(collection)) revert NotRegistered();
        if (IERC721(collection).ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken();
        if (
            IERC721(collection).getApproved(tokenId) != address(this) &&
            !IERC721(collection).isApprovedForAll(msg.sender, address(this))
        ) revert NotApproved();
        if (price == 0) revert BadPrice();

        uint256 existing = activeListing[collection][tokenId];
        if (existing != 0) _close(existing - 1);

        listingId = ++listingCount;
        listings[listingId] = Listing({
            seller: msg.sender,
            collection: collection,
            tokenId: tokenId,
            price: price,
            active: true
        });
        activeListing[collection][tokenId] = listingId + 1;

        emit Listed(listingId, collection, tokenId, msg.sender, price);
    }

    function updatePrice(uint256 listingId, uint256 price) external {
        Listing storage listing = _listing(listingId);
        if (listing.seller != msg.sender) revert NotSeller();
        if (price == 0) revert BadPrice();
        listing.price = price;
        emit PriceUpdated(listingId, price);
    }

    function cancel(uint256 listingId) external {
        Listing storage listing = _listing(listingId);
        if (listing.seller != msg.sender) revert NotSeller();
        _close(listingId);
        emit Delisted(listingId);
    }

    function buy(uint256 listingId) external payable nonReentrant {
        Listing storage listing = _listing(listingId);
        if (msg.value != listing.price) revert WrongValue(listing.price);

        address seller = listing.seller;
        address collection = listing.collection;
        uint256 tokenId = listing.tokenId;
        uint256 price = listing.price;

        // Listings are non-custodial: the seller must still own the NFT.
        if (IERC721(collection).ownerOf(tokenId) != seller) revert NotOwnerOfToken();

        // Reserve the protocol fee before calculating the artist's royalty.
        uint256 fee = Math.mulDiv(price, feeBps, 10_000);
        uint256 royaltyAvailable = price - fee;
        (address royaltyReceiver, uint256 royalty) = _royaltyInfo(collection, tokenId, price);
        if (royaltyReceiver == address(0)) {
            royalty = 0;
        } else if (royalty > royaltyAvailable) {
            royalty = royaltyAvailable;
        }
        uint256 sellerProceeds = royaltyAvailable - royalty;

        _close(listingId);

        // Safe delivery prevents a contract buyer without IERC721Receiver from
        // silently receiving an NFT it cannot manage.
        IERC721(collection).safeTransferFrom(seller, msg.sender, tokenId);

        if (royalty > 0) credits[royaltyReceiver] += royalty;
        if (fee > 0) credits[treasury] += fee;
        if (sellerProceeds > 0) credits[seller] += sellerProceeds;

        emit Sold(listingId, msg.sender, price, royalty, fee);
    }

    function withdraw() external nonReentrant {
        uint256 amount = credits[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        credits[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function setRegistry(VectolithRegistry registry_) external onlyOwner {
        if (address(registry_) == address(0)) revert ZeroAddress();
        registry = registry_;
        emit RegistrySet(address(registry_));
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function setFee(uint96 feeBps_) external onlyOwner {
        if (feeBps_ > 500) revert FeeTooHigh();
        feeBps = feeBps_;
        emit FeeSet(feeBps_);
    }

    function _royaltyInfo(address collection, uint256 tokenId, uint256 salePrice)
        private
        view
        returns (address receiver, uint256 royalty)
    {
        (bool supportsCall, bytes memory supportsData) = collection.staticcall(
            abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x2a55205a))
        );
        if (!supportsCall || supportsData.length != 32) revert InvalidInterfaceResponse();

        uint256 supportedWord;
        assembly {
            supportedWord := mload(add(supportsData, 32))
        }
        if (supportedWord > 1) revert InvalidInterfaceResponse();
        if (supportedWord == 0) return (address(0), 0);

        (bool royaltyCall, bytes memory royaltyData) = collection.staticcall(
            abi.encodeWithSignature("royaltyInfo(uint256,uint256)", tokenId, salePrice)
        );
        if (!royaltyCall || royaltyData.length != 64) revert RoyaltyQueryFailed();

        uint256 receiverWord;
        assembly {
            receiverWord := mload(add(royaltyData, 32))
            royalty := mload(add(royaltyData, 64))
        }
        if (receiverWord >> 160 != 0) revert RoyaltyQueryFailed();
        receiver = address(uint160(receiverWord));
    }

    function _listing(uint256 listingId) private view returns (Listing storage listing) {
        listing = listings[listingId];
        if (listing.seller == address(0) || !listing.active) revert Inactive();
    }

    function _close(uint256 listingId) private {
        Listing storage listing = listings[listingId];
        listing.active = false;
        if (activeListing[listing.collection][listing.tokenId] == listingId + 1) {
            delete activeListing[listing.collection][listing.tokenId];
        }
    }
}
