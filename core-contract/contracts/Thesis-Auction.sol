// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Thesis Auction
/// @author
/// @notice This contract manages auctions for thesis NFTs with secure bidding and claiming mechanisms.
/// @dev Implements Ownable, ReentrancyGuard, and Pausable for security and control.
interface IThesisNFT is IERC721 {
    /// @dev Returns the total supply of NFTs.
    function totalSupply() external view returns (uint256);
    /// @dev Returns the maximum supply of NFTs.
    function maxSupply() external view returns (uint256);
    /// @dev Returns whether the auction has started.
    function auctionStarted() external view returns (bool);
    /// @dev Reveals the file associated with a tokenId.
    function revealFile(uint256 tokenId) external;
    /// @dev Returns the owner of a given tokenId.
    function ownerOf(uint256 tokenId) external view returns (address);
    /// @dev Safely transfers a token from one address to another.
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    /// @dev Checks if a user has minted an NFT.
    function hasMinted(address user) external view returns (bool);
}

contract ThesisAuction is Ownable, ReentrancyGuard, Pausable {
    using Address for address payable;

    /// @dev The Thesis NFT contract interface.
    IThesisNFT public immutable thesisNFT;
    /// @dev The platform wallet address for fee collection.
    address payable public immutable platformWallet;
    /// @dev The owner of the NFTs being auctioned.
    address public immutable nftOwner;

    /// @dev Platform fee percentage (default 5%).
    uint256 public platformFeePercent = 5;
    /// @dev Maximum allowed bid amount.
    uint256 public maxBidAmount = 100 ether;
    /// @dev Minimum increment for bids.
    uint256 public immutable bidIncrement = 0.01 ether;
    /// @dev Time window before auction end to allow extension.
    uint256 public immutable extensionWindow = 5 minutes;
    /// @dev Time to extend the auction if bid placed near end.
    uint256 public immutable extensionTime = 10 minutes;
    /// @dev Starting price for the auction.
    uint256 public immutable auctionPrice;
    /// @dev Maximum number of NFT deposits allowed.
    uint256 public immutable maxDeposits = 10;
    /// @dev Current count of deposited NFTs.
    uint256 public depositedCount;
    /// @dev Delay before auction can be cancelled.
    uint256 public immutable cancelDelay = 5 minutes;
    /// @dev Maximum duration allowed for an auction.
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    /// @dev Maximum number of auction extensions allowed.
    uint256 public constant MAX_EXTENSIONS = 3;

    /// @dev Struct representing a bid.
    struct Bid {
        /// @dev Address of the bidder.
        address bidder;
        /// @dev Amount of the bid.
        uint256 amount;
        /// @dev Timestamp of the bid.
        uint64 timestamp;
    }

    /// @dev Struct representing auction information.
    struct AuctionInfo {
        /// @dev Auction end time as a timestamp.
        uint256 endTime;
        /// @dev Highest bid amount.
        uint256 highestBid;
        /// @dev Address of the highest bidder.
        address highestBidder;
        /// @dev Whether the NFT has been claimed.
        bool claimed;
        /// @dev Whether the auction is active.
        bool active;
        /// @dev Last modification timestamp.
        uint256 lastModified;
        /// @dev Number of extensions used.
        uint8 extensions;
    }

    /// @dev Mapping to track deposited NFTs by tokenId.
    mapping(uint256 => bool) public isDeposited;
    /// @dev Mapping to track sold NFTs by tokenId.
    mapping(uint256 => bool) public isSold;
    /// @dev Mapping to track winners of tokens.
    mapping(uint256 => address) public tokenWinners;
    /// @dev Mapping to store auction information by tokenId.
    mapping(uint256 => AuctionInfo) public auctionInfo;
    /// @dev Mapping to store bid history by tokenId.
    mapping(uint256 => Bid[]) private _bidHistory;
    /// @dev Mapping to track total bids by user per tokenId.
    mapping(uint256 => mapping(address => uint256)) public userBidTotals;
    /// @dev Mapping to track withdrawable balances by address.
    mapping(address => uint256) public withdrawable;
    /// @dev Mapping to track who deposited each tokenId.
    mapping(uint256 => address) public depositSender;
    /// @dev Mapping to track authorized depositors.
    mapping(address => bool) public authorizedDepositors;

    /// @dev Emitted when an auction is started.
    event AuctionStarted(uint256 tokenId, uint256 price);
    /// @dev Emitted when an auction ends.
    event AuctionEnded(uint256 tokenId, address winner, uint256 amount);
    /// @dev Emitted when an NFT is deposited.
    event NFTDeposited(uint256 tokenId);
    /// @dev Emitted when an NFT is claimed by the winner.
    event Claimed(address claimer, uint256 tokenId);
    /// @dev Emitted when the platform fee is updated.
    event PlatformFeeUpdated(uint256 newFeePercent);
    /// @dev Emitted when an auction is cancelled.
    event AuctionCancelled(uint256 tokenId);
    /// @dev Emitted when an emergency withdrawal is made.
    event EmergencyWithdrawal(address owner, uint256 amount);
    /// @dev Emitted when a refund is issued to a bidder.
    event RefundIssued(address bidder, uint256 amount);
    /// @dev Emitted when a bid is placed.
    event BidPlaced(uint256 tokenId, address bidder, uint256 amount);
    /// @dev Emitted when a refund is withdrawn.
    event RefundWithdrawn(address user, uint256 amount);
    /// @dev Emitted when revealFile call fails.
    event RevealFileFailed(uint256 tokenId);
    /// @dev Emitted when an NFT is reclaimed by the owner.
    event NFTReclaimed(uint256 tokenId);

    /// @dev Modifier to restrict access to NFT owner.
    modifier onlyNftOwner(uint256 tokenId) {
        require(msg.sender == depositSender[tokenId], "Not NFT owner");
        _;
    }

    /// @dev Modifier to check if auction exists for tokenId.
    modifier auctionExists(uint256 tokenId) {
        require(isDeposited[tokenId], "NFT not deposited");
        _;
    }

    /// @dev Modifier to enforce delay before certain actions.
    modifier onlyAfterDelay(uint256 tokenId) {
        require(block.timestamp > auctionInfo[tokenId].lastModified + cancelDelay, "Must wait");
        _;
    }

    /// @dev Constructor to initialize the contract with NFT address, initial price, owner, and platform wallet.
    /// @param thesisNFTAddress Address of the Thesis NFT contract.
    /// @param initialPrice Starting price for auctions.
    /// @param _nftOwner Owner of the NFTs.
    /// @param _platformWallet Wallet to receive platform fees.
    constructor(address thesisNFTAddress, uint256 initialPrice, address _nftOwner, address payable _platformWallet)
        Ownable(msg.sender)
        Pausable()
    {
        require(thesisNFTAddress != address(0), "Invalid NFT address");
        require(_nftOwner != address(0), "Invalid owner");
        require(_platformWallet != address(0), "Invalid wallet");
        require(initialPrice > 0, "Initial price must be positive");

        thesisNFT = IThesisNFT(thesisNFTAddress);
        auctionPrice = initialPrice;
        nftOwner = _nftOwner;
        platformWallet = _platformWallet;
        authorizedDepositors[msg.sender] = true;
    }

    /// @dev Pauses the contract, disabling certain functions.
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Unpauses the contract, enabling functions.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Sets the platform fee percentage.
    /// @param newFee New fee percentage (max 10).
    function setPlatformFeePercent(uint256 newFee) external onlyOwner {
        require(newFee <= 10, "Fee too high");
        platformFeePercent = newFee;
        emit PlatformFeeUpdated(newFee);
    }

    /// @dev Sets the maximum bid amount allowed.
    /// @param newMaxBid New maximum bid amount.
    function setMaxBidAmount(uint256 newMaxBid) external onlyOwner {
        require(newMaxBid >= auctionPrice, "Invalid max bid");
        maxBidAmount = newMaxBid;
    }

    /// @dev Starts an auction for a given tokenId and duration.
    /// @param tokenId The NFT token ID to auction.
    /// @param duration Duration of the auction in seconds.
    function startAuction(uint256 tokenId, uint256 duration) external onlyOwner whenNotPaused auctionExists(tokenId) {
        require(!auctionInfo[tokenId].active, "Auction already started");
        require(duration <= MAX_AUCTION_DURATION, "Duration too long");
        require(thesisNFT.auctionStarted(), "Auction not ready");
        require(thesisNFT.ownerOf(tokenId) == address(this), "NFT not owned by contract");

        auctionInfo[tokenId] = AuctionInfo({
            endTime: block.timestamp + duration,
            highestBid: 0,
            highestBidder: address(0),
            claimed: false,
            active: true,
            lastModified: block.timestamp,
            extensions: 0
        });

        emit AuctionStarted(tokenId, auctionPrice);
    }

    /// @dev Places a bid on an active auction.
    /// @param tokenId The NFT token ID being bid on.
    function placeBid(uint256 tokenId) external payable nonReentrant whenNotPaused auctionExists(tokenId) {
        // Restrict to minters only
        require(thesisNFT.hasMinted(msg.sender), "Only minters can bid");
        AuctionInfo storage auction = auctionInfo[tokenId];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value > 0, "Zero bid");
        uint256 minBid = auction.highestBid == 0 ? auctionPrice : auction.highestBid + bidIncrement;
        require(msg.value >= minBid, "Bid too low");
        require(msg.value <= maxBidAmount, "Bid too high");
        if (auction.highestBidder != address(0)) {
            withdrawable[auction.highestBidder] += auction.highestBid;
            emit RefundIssued(auction.highestBidder, auction.highestBid);
        }
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.lastModified = block.timestamp;
        if (auction.endTime - block.timestamp < extensionWindow && auction.extensions < MAX_EXTENSIONS) {
            auction.endTime = block.timestamp + extensionTime;
            auction.extensions++;
        }
        userBidTotals[tokenId][msg.sender] += msg.value;
        _bidHistory[tokenId].push(Bid({ bidder: msg.sender, amount: msg.value, timestamp: uint64(block.timestamp) }));
        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    /// @dev Ends an active auction and records the winner.
    /// @param tokenId The NFT token ID of the auction.
    function endAuction(uint256 tokenId) external whenNotPaused auctionExists(tokenId) {
        AuctionInfo storage auction = auctionInfo[tokenId];
        require(auction.active, "Auction inactive");
        require(block.timestamp >= auction.endTime, "Auction not over");
        require(msg.sender == owner() || msg.sender == nftOwner, "Unauthorized");

        auction.active = false;
        isSold[tokenId] = true;
        tokenWinners[tokenId] = auction.highestBidder;

        emit AuctionEnded(tokenId, auction.highestBidder, auction.highestBid);
    }

    /// @dev Allows the winner to claim the NFT after auction ends.
    /// @param tokenId The NFT token ID to claim.
    function claimNFT(uint256 tokenId) external nonReentrant auctionExists(tokenId) {
        AuctionInfo storage auction = auctionInfo[tokenId];
        require(isSold[tokenId], "NFT not sold");
        require(!auction.claimed, "Already claimed");
        require(msg.sender == auction.highestBidder, "Not winner");
        require(thesisNFT.ownerOf(tokenId) == address(this), "NFT not owned");

        auction.claimed = true;

        uint256 fee = auction.highestBid * platformFeePercent / 100;
        uint256 sellerAmount = auction.highestBid - fee;

        withdrawable[nftOwner] += sellerAmount;
        withdrawable[platformWallet] += fee;

        try thesisNFT.revealFile{gas: 100_000}(tokenId) {
        } catch {
            emit RevealFileFailed(tokenId);
        }

        thesisNFT.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Claimed(msg.sender, tokenId);
    }

    /// @dev Cancels an active auction after a delay.
    /// @param tokenId The NFT token ID of the auction.
    function cancelAuction(uint256 tokenId) external onlyOwner auctionExists(tokenId) onlyAfterDelay(tokenId) nonReentrant {
        AuctionInfo storage auction = auctionInfo[tokenId];
        require(auction.active, "Not active");
        auction.active = false;

        if (auction.highestBidder != address(0)) {
            withdrawable[auction.highestBidder] += auction.highestBid;
            emit RefundIssued(auction.highestBidder, auction.highestBid);
        }

        emit AuctionCancelled(tokenId);
    }

    /// @dev Allows the NFT owner to reclaim an NFT if auction is inactive and unsold.
    /// @param tokenId The NFT token ID to reclaim.
    function reclaimNFT(uint256 tokenId) external auctionExists(tokenId) {
        require(msg.sender == depositSender[tokenId], "Not original depositor");
        AuctionInfo storage auction = auctionInfo[tokenId];
        require(!auction.active && !isSold[tokenId], "Cannot reclaim active or sold NFT");

        thesisNFT.safeTransferFrom(address(this), depositSender[tokenId], tokenId);
        isDeposited[tokenId] = false;
        emit NFTReclaimed(tokenId);
    }

    /// @dev Allows the owner to withdraw platform fees during emergency when paused.
    function emergencyWithdraw() external onlyOwner whenPaused {
        uint256 amount = withdrawable[platformWallet];
        require(amount > 0, "No funds to withdraw");
        withdrawable[platformWallet] = 0;
        platformWallet.sendValue(amount);
        emit EmergencyWithdrawal(msg.sender, amount);
    }

    /// @dev Allows users to withdraw their refundable balances.
    function withdrawFunds() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        withdrawable[msg.sender] = 0;
        payable(msg.sender).sendValue(amount);
        emit RefundWithdrawn(msg.sender, amount);
    }

    /// @dev Returns the full bid history for a tokenId.
    /// @param tokenId The NFT token ID.
    /// @return Array of Bid structs representing the bid history.
    function getBidHistory(uint256 tokenId) external view returns (Bid[] memory) {
        return _bidHistory[tokenId];
    }

    /// @dev Returns a slice of the bid history for pagination.
    /// @param tokenId The NFT token ID.
    /// @param start Starting index of the slice.
    /// @param count Number of bids to return.
    /// @return Array of Bid structs representing the slice of bid history.
    function getBidHistorySlice(uint256 tokenId, uint256 start, uint256 count) external view returns (Bid[] memory) {
        Bid[] storage history = _bidHistory[tokenId];
        require(start < history.length, "Invalid start");
        uint256 end = start + count > history.length ? history.length : start + count;

        Bid[] memory slice = new Bid[](end - start);
        for (uint256 i = start; i < end; i++) {
            slice[i - start] = history[i];
        }
        return slice;
    }

    /// @dev Handles the receipt of an NFT.
    /// @param from The address which sent the NFT.
    /// @param tokenId The NFT token ID which was received.
    /// @return The selector to confirm token receipt.
    function onERC721Received(address /*operator*/, address from, uint256 tokenId, bytes calldata /*data*/) external whenNotPaused returns (bytes4) {
        require(msg.sender == address(thesisNFT), "Unrecognized NFT");
        require(!isDeposited[tokenId], "Already deposited");
        require(authorizedDepositors[from], "Unauthorized depositor");
        require(depositedCount < maxDeposits, "Max deposits reached");

        isDeposited[tokenId] = true;
        depositSender[tokenId] = from;
        depositedCount++;

        emit NFTDeposited(tokenId);
        return this.onERC721Received.selector;
    }

    /// @dev Rejects any direct ETH transfers to the contract.
    receive() external payable {
        revert("Send ETH via bid only");
    }

    /// @dev Rejects any fallback calls to the contract.
    fallback() external payable {
        revert("Invalid fallback call");
    }

    /// @dev Allows the owner to authorize or revoke authorization for a depositor.
    /// @param depositor The address to authorize or revoke authorization for.
    /// @param isAuthorized Whether to authorize or revoke authorization for the depositor.
    function setAuthorizedDepositor(address depositor, bool isAuthorized) external onlyOwner {
        authorizedDepositors[depositor] = isAuthorized;
    }
}