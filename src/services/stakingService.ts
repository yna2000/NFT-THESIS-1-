import Web3 from "web3";
import contractAddresses from "../config/contractAddresses";
import StakingABI from "coreContractArtifacts/contracts/Staking.sol/Staking.json";

export interface StakePosition {
  amount: number;
  stakedAt: Date;
  unlockTime: Date;
  hasStaked: boolean;
}

export interface StakingConfig {
  minimumStake: number;
  discountPercentage: number;
  lockPeriod: number;
}

export class StakingService {
  private static instance: StakingService;
  private web3: Web3;
  private contract: any;
  private walletAddress: string | null = null;

  private constructor() {
    this.web3 = new Web3((window as any).ethereum);
    this.contract = new this.web3.eth.Contract(StakingABI.abi, contractAddresses.staking);
  }

  public static getInstance(): StakingService {
    if (!StakingService.instance) {
      StakingService.instance = new StakingService();
    }
    return StakingService.instance;
  }

  public setWalletAddress(address: string): void {
    this.walletAddress = address;
  }

  async stakeTokens(amount: number): Promise<StakePosition> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    try {
      // Check minimum stake requirement (3 tCORE2)
      const minimumStake = await this.contract.methods.minimumStake().call();
      const minimumStakeInCORE = Number(this.web3.utils.fromWei(minimumStake, 'ether'));
      
      if (amount < minimumStakeInCORE) {
        throw new Error(`Minimum stake amount is ${minimumStakeInCORE} tCORE2 for discount eligibility`);
      }

      console.log(`Attempting to stake ${amount} tCORE2 tokens`);
      console.log(`Minimum stake required: ${minimumStakeInCORE} tCORE2`);
      
      // Convert amount to wei (native token units)
      const amountInWei = this.web3.utils.toWei(amount.toString(), 'ether');
      
      // Call stake() with the value
      const tx = await this.contract.methods
        .stake()
        .send({ 
          from: this.walletAddress,
          value: amountInWei,
          gas: 200000,
          maxPriorityFeePerGas: this.web3.utils.toWei('1', 'gwei'),
          maxFeePerGas: this.web3.utils.toWei('2', 'gwei')
        });

      console.log('Staking transaction:', tx);

      const stakedAt = new Date();
      const unlockTime = new Date(stakedAt.getTime() + 30 * 24 * 60 * 60 * 1000); // 30 days

      return {
        amount,
        stakedAt,
        unlockTime,
        hasStaked: true
      };
    } catch (error) {
      console.error('Staking failed:', error);
      throw error;
    }
  }

  async unstakeTokens(): Promise<{ amount: number }> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }

    try {
      console.log('Attempting to unstake tokens');
      
      const tx = await this.contract.methods
        .unstake()
        .send({ 
          from: this.walletAddress,
          gas: 150000,
          maxPriorityFeePerGas: this.web3.utils.toWei('1', 'gwei'),
          maxFeePerGas: this.web3.utils.toWei('2', 'gwei')
        });

      console.log('Unstaking transaction:', tx);

      // Get the user's stake amount before unstaking
      const userStake = await this.contract.methods.stakes(this.walletAddress).call();
      const amount = Number(this.web3.utils.fromWei(userStake.amount, 'ether'));

      return { amount };
    } catch (error) {
      console.error('Unstaking failed:', error);
      throw error;
    }
  }

  async getTotalStaked(): Promise<number> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }
    
    try {
      const userStake = await this.contract.methods.stakes(this.walletAddress).call();
      return Number(this.web3.utils.fromWei(userStake.amount, 'ether'));
    } catch (error) {
      console.error('Failed to get total staked:', error);
      return 0;
    }
  }

  async hasDiscountEligibility(): Promise<boolean> {
    if (!this.walletAddress) {
      return false;
    }
    
    try {
      const discountPercent = await this.contract.methods.getDiscountPercentage(this.walletAddress).call();
      return Number(discountPercent) > 0;
    } catch (error) {
      console.error('Failed to check discount eligibility:', error);
      return false;
    }
  }

  async getUserStakes(): Promise<StakePosition[]> {
    if (!this.walletAddress) {
      throw new Error("Wallet address not set");
    }
    
    try {
      const userStake = await this.contract.methods.stakes(this.walletAddress).call();
      const stakeAmount = Number(this.web3.utils.fromWei(userStake.amount, 'ether'));
      
      if (stakeAmount > 0 && userStake.hasStaked) {
        const unlockTime = new Date(Number(userStake.unlockTime) * 1000);
        const stakedAt = new Date(unlockTime.getTime() - 30 * 24 * 60 * 60 * 1000); // Calculate from unlock time
        
        const stake: StakePosition = {
          amount: stakeAmount,
          stakedAt,
          unlockTime,
          hasStaked: userStake.hasStaked
        };
        return [stake];
      }
      return [];
    } catch (error) {
      console.error('Error fetching user stakes:', error);
      return [];
    }
  }

  async getUserUnlockTime(): Promise<Date | null> {
    if (!this.walletAddress) {
      return null;
    }
    
    try {
      const userStake = await this.contract.methods.stakes(this.walletAddress).call();
      if (userStake.hasStaked) {
        return new Date(Number(userStake.unlockTime) * 1000);
      }
      return null;
    } catch (error) {
      console.error('Error fetching unlock time:', error);
      return null;
    }
  }

  async isEligibleForDiscount(): Promise<boolean> {
    if (!this.walletAddress) {
      return false;
    }
    
    try {
      return await this.contract.methods.isEligibleForDiscount(this.walletAddress).call();
    } catch (error) {
      console.error('Error checking discount eligibility:', error);
      return false;
    }
  }

  async getStakingConfig(): Promise<StakingConfig> {
    try {
      const minimumStake = await this.contract.methods.minimumStake().call();
      const discountPercent = await this.contract.methods.discountPercent().call();
      
      return {
        minimumStake: Number(this.web3.utils.fromWei(minimumStake, 'ether')),
        discountPercentage: Number(discountPercent),
        lockPeriod: 30 // Fixed 30 days
      };
    } catch (error) {
      console.error('Failed to get staking config:', error);
      return {
        minimumStake: 3,
        discountPercentage: 20,
        lockPeriod: 30
      };
    }
  }
}