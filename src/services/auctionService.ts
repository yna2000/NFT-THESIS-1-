import Web3 from "web3";
import contractAddresses from "../config/contractAddresses";
import ThesisAuctionABI from "coreContractArtifacts/contracts/Thesis-Auction.sol/ThesisAuction.json";
import { NFTContractService, MintedNFT } from './nftContractService';

export interface AuctionConfig {
  startingPrice: number;
  reservePrice: number;
  duration: number; // in hours
  onlyMintersCanBid: boolean;
  escrowEnabled: boolean;
}

export interface Bid {
  bidder: string;
  amount: number;
  timestamp: Date;
  transactionHash: string;
}

export interface Auction {
  id: string;
  nftTokenId: string;
  seller: string;
  config: AuctionConfig;
  bids: Bid[];
  startTime: Date;
  endTime: Date;
  status: 'active' | 'ended' | 'cancelled';
  winner?: string;
  finalPrice?: number;
  escrowFunds: Map<string, number>;
}

export class AuctionService {
  private static instance: AuctionService;
  private web3: Web3;
  private contract: any;
  private walletAddress: string | null = null;
  private auctions: Map<string, Auction> = new Map();
  private nftService = NFTContractService.getInstance();

  static getInstance(): AuctionService {
    if (!AuctionService.instance) {
      AuctionService.instance = new AuctionService();
    }
    return AuctionService.instance;
  }

  constructor() {
    this.web3 = new Web3((window as any).ethereum);
    this.contract = new this.web3.eth.Contract(
      ThesisAuctionABI.abi,
      contractAddresses.thesisAuction
    );
  }

  async setWalletAddress(address: string) {
    this.walletAddress = address;
  }

  async createAuction(
    nftTokenId: string,
    seller: string,
    config: AuctionConfig
  ): Promise<string> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    const auctionId = `auction_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const startTime = new Date();
    const endTime = new Date(startTime.getTime() + (config.duration * 60 * 60 * 1000));

    const auction: Auction = {
      id: auctionId,
      nftTokenId,
      seller,
      config,
      bids: [],
      startTime,
      endTime,
      status: 'active',
      escrowFunds: new Map()
    };

    this.auctions.set(auctionId, auction);
    return auctionId;
  }

  async placeBid(auctionId: string, bidder: string, amount: number): Promise<boolean> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    const auction = this.auctions.get(auctionId);
    if (!auction) {
      throw new Error('Auction not found');
    }

    if (auction.status !== 'active') {
      throw new Error('Auction is not active');
    }

    if (new Date() > auction.endTime) {
      throw new Error('Auction has ended');
    }

    // Check if only minters can bid
    if (auction.config.onlyMintersCanBid) {
      const userNFTs = await this.nftService.getUserMintedNFTs();
      const hasNFTFromThesis = userNFTs.some(nft => 
        nft.tokenId.split('_')[0] === auction.nftTokenId.split('_')[0]
      );
      
      if (!hasNFTFromThesis) {
        throw new Error('Only minters of this thesis can participate in the auction');
      }
    }

    const currentHighestBid = auction.bids.length > 0 
      ? Math.max(...auction.bids.map(bid => bid.amount))
      : auction.config.startingPrice;

    if (amount <= currentHighestBid) {
      throw new Error('Bid must be higher than current highest bid');
    }

    if (amount < auction.config.reservePrice) {
      throw new Error('Bid must meet reserve price');
    }

    // Simulate escrow deposit
    await new Promise(resolve => setTimeout(resolve, 1500));

    const bid: Bid = {
      bidder,
      amount,
      timestamp: new Date(),
      transactionHash: `0x${Math.random().toString(16).substr(2, 64)}`
    };

    auction.bids.push(bid);
    
    // Add to escrow
    if (auction.config.escrowEnabled) {
      auction.escrowFunds.set(bidder, amount);
    }

    return true;
  }

  async endAuction(auctionId: string): Promise<Auction | null> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    const auction = this.auctions.get(auctionId);
    if (!auction) return null;

    auction.status = 'ended';
    
    if (auction.bids.length > 0) {
      const winningBid = auction.bids.reduce((highest, current) => 
        current.amount > highest.amount ? current : highest
      );
      
      auction.winner = winningBid.bidder;
      auction.finalPrice = winningBid.amount;

      // Release non-winner funds from escrow
      if (auction.config.escrowEnabled) {
        auction.escrowFunds.forEach((amount, bidder) => {
          if (bidder !== auction.winner) {
            // Simulate fund release
            console.log(`Releasing ${amount} CORE to ${bidder}`);
          }
        });
      }

      // Transfer NFT to winner and unblur it
      await this.nftService.unblurNFT(auction.nftTokenId);
    }

    return auction;
  }

  getActiveAuctions(): Auction[] {
    return Array.from(this.auctions.values()).filter(auction => 
      auction.status === 'active' && new Date() <= auction.endTime
    );
  }

  getAuction(auctionId: string): Auction | null {
    return this.auctions.get(auctionId) || null;
  }

  getUserBids(walletAddress: string): { auctionId: string; bid: Bid }[] {
    const userBids: { auctionId: string; bid: Bid }[] = [];
    
    this.auctions.forEach((auction, auctionId) => {
      const userBid = auction.bids.find(bid => bid.bidder === walletAddress);
      if (userBid) {
        userBids.push({ auctionId, bid: userBid });
      }
    });

    return userBids;
  }
}