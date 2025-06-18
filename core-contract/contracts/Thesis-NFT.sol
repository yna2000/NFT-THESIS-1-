// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// This contract is intended for deployment on SepoliaETH (chainId: 11155111) and tCORE2 (chainId: 1114) testnets as configured in hardhat.config.ts

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";

/// @title Thesis NFT
/// @author
/// @notice This contract manages the minting and distribution of thesis NFTs with staking-based discounts and auction functionality.
/// @dev Implements ERC721 standard with custom minting logic, staking integration, and auction state management.
interface IStaking {
    /// @dev Returns the discount percentage for a given user based on their staking amount.
    /// @param user The address of the user to check.
    /// @return The discount percentage (0-100).
    function getDiscountPercentage(address user) external view returns (uint256);
}

contract ThesisNFT is ERC721, Ownable {
    /// @dev Maximum number of NFTs that can be minted.
    uint256 public maxSupply;
    /// @dev Minimum number of NFTs required before auction can start.
    uint256 public minSupply;
    /// @dev Price per NFT in wei.
    uint256 public price;
    /// @dev Internal counter for token IDs, starts at 0.
    uint256 private _tokenIdCounter;
    /// @dev Flag indicating if the auction phase has started.
    bool public auctionStarted;

    /// @dev Reference to the staking contract for discount calculations.
    IStaking public stakingContract;

    /// @dev Base URI for token metadata.
    string private _baseTokenURI;
    /// @dev IPFS hash for the associated file.
    string public ipfsHash;

    /// @dev Mapping to track which addresses have already minted an NFT.
    mapping(address => bool) private _hasMinted;
    /// @dev Mapping to track which tokens have been revealed.
    mapping(uint256 => bool) private _revealedTokens;

    /// @dev Emitted when the auction phase begins.
    event AuctionStarted();
    /// @dev Emitted when the NFT price is updated.
    event PriceUpdated(uint256 newPrice);
    /// @dev Emitted when NFTs are minted.
    event Minted(address indexed to, uint256 amount, uint256 startTokenId);
    /// @dev Emitted for debugging minting process.
    event DebugMintStep(string step, uint256 value);
    /// @dev Emitted when the IPFS hash is set.
    event IpfsHashSet(string ipfsHash);
    /// @dev Emitted when a file is revealed for a token.
    event FileRevealed(uint256 tokenId);

    /// @dev Constructor to initialize the NFT contract with basic parameters.
    /// @param name_ The name of the NFT collection.
    /// @param symbol_ The symbol of the NFT collection.
    /// @param maxSupply_ The maximum number of NFTs that can be minted.
    /// @param minSupply_ The minimum number of NFTs required before auction starts.
    /// @param price_ The price per NFT in wei.
    /// @param initialOwner The initial owner of the contract.
    /// @param stakingContractAddress The address of the staking contract.
    /// @param baseTokenURI_ The base URI for token metadata.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 minSupply_,
        uint256 price_,
        address initialOwner,
        address stakingContractAddress,
        string memory baseTokenURI_
    ) ERC721(name_, symbol_) Ownable(initialOwner) {
        require(minSupply_ >= 40, "Minimum supply must be at least 40");
        require(maxSupply_ <= 100, "Maximum supply must be at most 100");
        require(minSupply_ <= maxSupply_, "Min supply must be <= max supply");

        maxSupply = maxSupply_;
        minSupply = minSupply_;
        price = price_;
        _tokenIdCounter = 0; // Start token IDs at 0 to match standard ERC721 behavior
        auctionStarted = false;
        stakingContract = IStaking(stakingContractAddress);
        _baseTokenURI = baseTokenURI_;
    }

    /// @dev Returns the total number of NFTs minted so far.
    /// @return The current total supply of NFTs.
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /// @dev Allows users to mint NFTs with staking-based discounts.
    /// @param amount The number of NFTs to mint (must be 1).
    function mint(uint256 amount) external payable {
        require(!auctionStarted, "Minting is closed, auction started");
        require(amount == 1, "Can only mint 1 NFT per wallet");
        require(!_hasMinted[msg.sender], "Address has already minted");
        require(totalSupply() + amount <= maxSupply, "Exceeds max supply");

        uint256 effectivePrice = price;
        uint256 discountPercent = stakingContract.getDiscountPercentage(msg.sender);
        if (discountPercent > 0) {
            uint256 discount = (price * discountPercent) / 100;
            effectivePrice = price - discount;
        }

        // Apply platform fee of 20%
        uint256 platformFee = (effectivePrice * 20) / 100;
        uint256 totalPrice = effectivePrice + platformFee;

        require(msg.value >= totalPrice * amount, "Insufficient ETH sent");

        uint256 startTokenId = _tokenIdCounter;
        for (uint256 i = 0; i < amount; i++) {
            emit DebugMintStep("Before minting token", _tokenIdCounter);
            console.log("Before minting token, tokenId:", _tokenIdCounter);
            _mint(msg.sender, _tokenIdCounter);
            emit DebugMintStep("After minting token", _tokenIdCounter);
            console.log("After minting token, tokenId:", _tokenIdCounter);
            _tokenIdCounter++;
        }

        _hasMinted[msg.sender] = true;

        emit DebugMintStep("After minting loop", _tokenIdCounter);
        console.log("After minting loop, final tokenId:", _tokenIdCounter);

        emit Minted(msg.sender, amount, startTokenId);

        // If min supply reached, start auction
        if (totalSupply() >= minSupply) {
            auctionStarted = true;
            emit AuctionStarted();
        }
    }

    /// @dev Allows the owner to update the NFT price before auction starts.
    /// @param newPrice The new price per NFT in wei.
    function setPrice(uint256 newPrice) external onlyOwner {
        require(!auctionStarted, "Cannot change price after auction started");
        price = newPrice;
        emit PriceUpdated(newPrice);
    }

    /// @dev Allows the owner to withdraw accumulated ETH from the contract.
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @dev Checks if a user owns at least one NFT.
    /// @param user The address to check.
    /// @return True if the user owns at least one NFT, false otherwise.
    function ownsNFT(address user) external view returns (bool) {
        return balanceOf(user) > 0;
    }

    /// @dev Returns the metadata URI for a given token ID.
    /// @param tokenId The ID of the token.
    /// @return The complete metadata URI for the token.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId), ".json"));
    }

    /// @dev Allows the owner to set the base URI for token metadata.
    /// @param baseURI The new base URI.
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /// @dev Returns the base URI for token metadata.
    /// @return The current base URI.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Allows the owner to set the IPFS hash for the associated file.
    /// @param _ipfsHash The IPFS hash to set.
    function setIpfsHash(string memory _ipfsHash) external onlyOwner {
        ipfsHash = _ipfsHash;
        emit IpfsHashSet(_ipfsHash);
    }

    /// @dev Reveals the file associated with a token ID.
    /// @param tokenId The ID of the token to reveal.
    function revealFile(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!_revealedTokens[tokenId], "File already revealed");
        _revealedTokens[tokenId] = true;
        emit FileRevealed(tokenId);
    }

    /// @dev Checks if a user has minted an NFT.
    /// @param user The address to check.
    /// @return True if the user has minted, false otherwise.
    function hasMinted(address user) external view returns (bool) {
        return _hasMinted[user];
    }
}