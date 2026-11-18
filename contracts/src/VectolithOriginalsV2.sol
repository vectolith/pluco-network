// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title VectolithOriginalsV2
 * @notice Hardened successor proposal to the immutable V1 Originals collection.
 *
 * Primary-mint protocol fees are credited for pull withdrawal. Treasury addresses
 * must be non-zero, and provenance can be committed only once. This contract is
 * not deployed and does not upgrade or replace any existing collection.
 */
contract VectolithOriginalsV2 is ERC721, ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard {
    uint256 public immutable maxSupply;
    uint256 public immutable mintPrice;
    uint256 public immutable maxPerWallet;

    uint256 public totalMinted;
    uint256 public proceedsBalance;
    bool public saleOpen;
    string public provenance;
    bool public provenanceFrozen;

    address public treasury;
    uint96 public feeBps;

    mapping(address => uint256) public mintedBy;
    mapping(address => uint256) public credits;

    event SaleToggled(bool open);
    event ProvenanceCommitted(string provenanceHash);
    event ArtMinted(address indexed to, uint256 indexed tokenId, string uri);
    event FeeAccrued(address indexed treasury, uint256 amount);
    event TreasurySet(address treasury);
    event FeeSet(uint96 feeBps);
    event Withdrawn(address indexed account, uint256 amount);
    event ProceedsWithdrawn(address indexed recipient, uint256 amount);

    error ZeroAddress();
    error SaleClosed();
    error SoldOut();
    error WrongPrice(uint256 expected, uint256 sent);
    error WalletLimit(uint256 limit);
    error BadSupply();
    error FeeTooHigh();
    error ProvenanceAlreadyCommitted();
    error EmptyProvenance();
    error NothingToWithdraw();
    error TransferFailed();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 mintPrice_,
        uint256 maxPerWallet_,
        address owner_,
        address royaltyReceiver_,
        address treasury_,
        uint96 feeBps_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        if (maxSupply_ == 0) revert BadSupply();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (feeBps_ > 1_000) revert FeeTooHigh();

        maxSupply = maxSupply_;
        mintPrice = mintPrice_;
        maxPerWallet = maxPerWallet_ == 0 ? maxSupply_ : maxPerWallet_;
        treasury = treasury_;
        feeBps = feeBps_;
        _setDefaultRoyalty(royaltyReceiver_, 750);
    }

    function mint(string calldata uri) external payable nonReentrant returns (uint256 tokenId) {
        if (!saleOpen) revert SaleClosed();
        if (totalMinted >= maxSupply) revert SoldOut();
        if (msg.value != mintPrice) revert WrongPrice(mintPrice, msg.value);
        if (mintedBy[msg.sender] >= maxPerWallet) revert WalletLimit(maxPerWallet);

        tokenId = ++totalMinted;
        mintedBy[msg.sender] += 1;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);
        emit ArtMinted(msg.sender, tokenId, uri);

        uint256 fee = Math.mulDiv(mintPrice, feeBps, 10_000);
        if (fee > 0) {
            credits[treasury] += fee;
            emit FeeAccrued(treasury, fee);
        }
        proceedsBalance += mintPrice - fee;
    }

    function ownerMint(address to, string calldata uri) external onlyOwner returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (totalMinted >= maxSupply) revert SoldOut();

        tokenId = ++totalMinted;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        emit ArtMinted(to, tokenId, uri);
    }

    function setSaleOpen(bool open) external onlyOwner {
        saleOpen = open;
        emit SaleToggled(open);
    }

    function setProvenance(string calldata provenanceHash) external onlyOwner {
        if (provenanceFrozen) revert ProvenanceAlreadyCommitted();
        if (bytes(provenanceHash).length == 0) revert EmptyProvenance();
        provenance = provenanceHash;
        provenanceFrozen = true;
        emit ProvenanceCommitted(provenanceHash);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function setFeeBps(uint96 feeBps_) external onlyOwner {
        if (feeBps_ > 1_000) revert FeeTooHigh();
        feeBps = feeBps_;
        emit FeeSet(feeBps_);
    }

    function withdraw() external nonReentrant {
        uint256 amount = credits[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        credits[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawProceeds(address payable recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = proceedsBalance;
        if (amount == 0) revert NothingToWithdraw();

        proceedsBalance = 0;
        (bool ok, ) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit ProceedsWithdrawn(recipient, amount);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
