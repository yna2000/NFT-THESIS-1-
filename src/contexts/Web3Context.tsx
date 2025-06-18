import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import Web3 from 'web3';
import { useToast } from '@/hooks/use-toast';
import contractAddresses from '../config/contractAddresses';
import StakingABI from 'coreContractArtifacts/contracts/Staking.sol/Staking.json';
import ThesisNFTABI from 'coreContractArtifacts/contracts/Thesis-NFT.sol/ThesisNFT.json';
import ThesisAuctionABI from 'coreContractArtifacts/contracts/Thesis-Auction.sol/ThesisAuction.json';

declare global {
  interface Window {
    ethereum?: any;
  }
}

interface Web3ContextType {
  web3: Web3 | null;
  accounts: string[];
  currentAccount: string | null;
  isConnected: boolean;
  isCorrectNetwork: boolean;
  networkStatus: 'checking' | 'correct' | 'incorrect' | 'error';
  contracts: {
    staking: any;
    thesisNFT: any;
    thesisAuction: any;
  } | null;
  connectWallet: () => Promise<void>;
  disconnectWallet: () => void;
  switchToCoreTestnet: () => Promise<boolean>;
}

const Web3Context = createContext<Web3ContextType | undefined>(undefined);

const CORE_TESTNET_CONFIG = {
  chainId: '0x45a', // 1114 in hex (tCORE2 Chain ID)
  chainName: 'Core Blockchain TestNet',
  nativeCurrency: {
    name: 'tCORE2',
    symbol: 'tCORE2',
    decimals: 18,
  },
  rpcUrls: ['https://rpc.test2.btcs.network'],
  blockExplorerUrls: ['https://scan.test2.btcs.network'],
};

export const Web3Provider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [web3, setWeb3] = useState<Web3 | null>(null);
  const [accounts, setAccounts] = useState<string[]>([]);
  const [currentAccount, setCurrentAccount] = useState<string | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [isCorrectNetwork, setIsCorrectNetwork] = useState(false);
  const [networkStatus, setNetworkStatus] = useState<'checking' | 'correct' | 'incorrect' | 'error'>('checking');
  const [contracts, setContracts] = useState<{
    staking: any;
    thesisNFT: any;
    thesisAuction: any;
  } | null>(null);
  const { toast } = useToast();

  const initializeWeb3 = () => {
    if (typeof window.ethereum !== 'undefined') {
      const web3Instance = new Web3(window.ethereum);
      setWeb3(web3Instance);
      
      // Initialize contracts
      const stakingContract = new web3Instance.eth.Contract(
        StakingABI.abi,
        contractAddresses.staking
      );
      
      const thesisNFTContract = new web3Instance.eth.Contract(
        ThesisNFTABI.abi,
        contractAddresses.thesisNFT
      );
      
      const thesisAuctionContract = new web3Instance.eth.Contract(
        ThesisAuctionABI.abi,
        contractAddresses.thesisAuction
      );
      
      setContracts({
        staking: stakingContract,
        thesisNFT: thesisNFTContract,
        thesisAuction: thesisAuctionContract,
      });
      
      return web3Instance;
    }
    return null;
  };

  const checkNetwork = async () => {
    if (!window.ethereum) {
      setNetworkStatus('error');
      return;
    }
    
    setNetworkStatus('checking');
    
    try {
      const chainId = await window.ethereum.request({ method: 'eth_chainId' });
      const isCorrect = chainId === CORE_TESTNET_CONFIG.chainId;
      setIsCorrectNetwork(isCorrect);
      setNetworkStatus(isCorrect ? 'correct' : 'incorrect');
    } catch (error) {
      console.error('Error checking network:', error);
      setNetworkStatus('error');
      setIsCorrectNetwork(false);
    }
  };

  const addCoreTestnetToMetaMask = async () => {
    try {
      await window.ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [CORE_TESTNET_CONFIG],
      });
      
      toast({
        title: "Network Added",
        description: "CORE Testnet has been added to MetaMask",
      });
      
      setTimeout(checkNetwork, 1000);
      return true;
    } catch (error: any) {
      console.error('Failed to add Core Testnet:', error);
      toast({
        title: "Network Error",
        description: error.message || "Failed to add CORE Testnet to MetaMask",
        variant: "destructive",
      });
      return false;
    }
  };

  const switchToCoreTestnet = async (): Promise<boolean> => {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: CORE_TESTNET_CONFIG.chainId }],
      });
      
      toast({
        title: "Network Switched",
        description: "Successfully switched to CORE Testnet",
      });
      
      setTimeout(checkNetwork, 1000);
      return true;
    } catch (error: any) {
      if (error.code === 4902) {
        return await addCoreTestnetToMetaMask();
      }
      console.error('Failed to switch to Core Testnet:', error);
      toast({
        title: "Switch Failed",
        description: error.message || "Failed to switch to CORE Testnet",
        variant: "destructive",
      });
      return false;
    }
  };

  const connectWallet = async () => {
    if (!window.ethereum) {
      toast({
        title: "MetaMask Required",
        description: "Please install MetaMask to connect your wallet",
        variant: "destructive",
      });
      return;
    }

    try {
      // Initialize Web3 if not already done
      if (!web3) {
        initializeWeb3();
      }

      // Check and switch network if needed
      if (!isCorrectNetwork) {
        const networkSwitched = await switchToCoreTestnet();
        if (!networkSwitched) {
          return;
        }
      }

      // Request account access
      const accounts = await window.ethereum.request({
        method: 'eth_requestAccounts',
      });

      if (accounts.length > 0) {
        setAccounts(accounts);
        setCurrentAccount(accounts[0]);
        setIsConnected(true);
        
        // Update services with wallet address
        const { NFTContractService } = await import('../services/nftContractService');
        const { StakingService } = await import('../services/stakingService');
        
        NFTContractService.getInstance().setWalletAddress(accounts[0]);
        StakingService.getInstance().setWalletAddress(accounts[0]);
        
        toast({
          title: "Wallet Connected",
          description: `Connected to ${accounts[0].slice(0, 6)}...${accounts[0].slice(-4)}`,
        });
      }
    } catch (error: any) {
      console.error('Failed to connect wallet:', error);
      toast({
        title: "Connection Failed",
        description: error.message || "Failed to connect wallet. Please try again.",
        variant: "destructive",
      });
    }
  };

  const disconnectWallet = () => {
    setAccounts([]);
    setCurrentAccount(null);
    setIsConnected(false);
    setIsCorrectNetwork(false);
    setNetworkStatus('checking');
    
    toast({
      title: "Wallet Disconnected",
      description: "You have been logged out successfully",
    });
  };

  const handleAccountsChanged = (accounts: string[]) => {
    if (accounts.length === 0) {
      disconnectWallet();
    } else {
      setAccounts(accounts);
      setCurrentAccount(accounts[0]);
      setIsConnected(true);
      
      // Update services with new wallet address
      const updateServices = async () => {
        const { NFTContractService } = await import('../services/nftContractService');
        const { StakingService } = await import('../services/stakingService');
        
        NFTContractService.getInstance().setWalletAddress(accounts[0]);
        StakingService.getInstance().setWalletAddress(accounts[0]);
      };
      updateServices();
    }
  };

  const handleChainChanged = () => {
    checkNetwork();
  };

  useEffect(() => {
    const web3Instance = initializeWeb3();
    checkNetwork();

    if (window.ethereum) {
      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', handleChainChanged);
    }

    return () => {
      if (window.ethereum) {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
      }
    };
  }, []);

  const value: Web3ContextType = {
    web3,
    accounts,
    currentAccount,
    isConnected,
    isCorrectNetwork,
    networkStatus,
    contracts,
    connectWallet,
    disconnectWallet,
    switchToCoreTestnet,
  };

  return (
    <Web3Context.Provider value={value}>
      {children}
    </Web3Context.Provider>
  );
};

export const useWeb3 = (): Web3ContextType => {
  const context = useContext(Web3Context);
  if (context === undefined) {
    throw new Error('useWeb3 must be used within a Web3Provider');
  }
  return context;
};