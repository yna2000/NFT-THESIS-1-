import Web3 from "web3";
import contractAddresses from "@/config/contractAddresses";
import ThesisNFTABI from "coreContractArtifacts/contracts/Thesis-NFT.sol/ThesisNFT.json";

export interface NFTMetadata {
  title: string;
  author: string;
  university: string;
  year: number;
  field: string;
  description: string;
  ipfsHash: string;
  tags: string[];
}

export interface NFTMintingConfig {
  maxSupply: number;
  platformFeePercentage: number; // Platform fee (5%)
  authorRoyaltyPercentage: number; // Author royalty (10%)
  mintPrice: number;
  isBlurred: boolean;
  introOnly: boolean;
}

export interface MintedNFT {
  tokenId: string;
  owner: string;
  metadata: NFTMetadata;
  isBlurred: boolean;
  mintedAt: Date;
  transactionHash: string;
}

export class NFTContractService {
  private static instance: NFTContractService;
  private web3: Web3;
  private contract: any;
  private walletAddress: string | null = null;
  private mintedNFTs: Map<string, MintedNFT[]> = new Map();
  private nftConfigs: Map<string, NFTMintingConfig> = new Map();
  private walletMintCounts: Map<string, Set<string>> = new Map();

  static getInstance(): NFTContractService {
    if (!NFTContractService.instance) {
      NFTContractService.instance = new NFTContractService();
    }
    return NFTContractService.instance;
  }

  constructor() {
    this.web3 = new Web3((window as any).ethereum);
    this.contract = new this.web3.eth.Contract(
      ThesisNFTABI.abi,
      contractAddresses.thesisNFT
    );
  }

  async setWalletAddress(address: string) {
    this.walletAddress = address;
  }

  setNFTConfig(thesisId: string, config: NFTMintingConfig): void {
    this.nftConfigs.set(thesisId, config);
  }

  getNFTConfig(thesisId: string): NFTMintingConfig | null {
    return this.nftConfigs.get(thesisId) || null;
  }

  canUserMint(walletAddress: string, thesisId: string): boolean {
    const userMints = this.walletMintCounts.get(walletAddress) || new Set();
    return !userMints.has(thesisId);
  }

  getMintedCount(thesisId: string): number {
    const mints = this.mintedNFTs.get(thesisId) || [];
    return mints.length;
  }

  async mintNFT(
    thesisId: string,
    metadata: NFTMetadata,
    stakedAmount: number = 0
  ): Promise<MintedNFT> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    // Call the mint function on the contract
    const mintPrice = await this.contract.methods.mintPrice().call();
    const hasStakingDiscount = stakedAmount >= 100;
    const discountRate = hasStakingDiscount ? 0.2 : 0;
    const finalMintPrice = mintPrice * (1 - discountRate);

    const tx = await this.contract.methods
      .mint(thesisId, JSON.stringify(metadata))
      .send({ from: this.walletAddress, value: finalMintPrice });

    const tokenId = tx.events.Transfer.returnValues.tokenId;

    const mintedNFT: MintedNFT = {
      tokenId,
      owner: this.walletAddress,
      metadata,
      isBlurred: true,
      mintedAt: new Date(),
      transactionHash: tx.transactionHash,
    };

    // Record the mint
    const existingMints = this.mintedNFTs.get(thesisId) || [];
    this.mintedNFTs.set(thesisId, [...existingMints, mintedNFT]);

    // Track user mint for this thesis
    const userMints = this.walletMintCounts.get(this.walletAddress) || new Set();
    userMints.add(thesisId);
    this.walletMintCounts.set(this.walletAddress, userMints);

    return mintedNFT;
  }

  async getUserMintedNFTs(): Promise<MintedNFT[]> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    // Fetch minted NFTs for the user from the contract or backend
    // Placeholder: return empty array for now
    return [];
  }

  async unblurNFT(tokenId: string): Promise<boolean> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    // Call unblur function on the contract if exists
    // Placeholder: return true for now
    return true;
  }
}