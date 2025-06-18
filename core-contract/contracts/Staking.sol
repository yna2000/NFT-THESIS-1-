// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Staking Contract for NFT Discount
/// @author
/// @notice This contract manages tCORE2 staking for NFT minting discounts with 30-day lock period.
/// @dev Implements ReentrancyGuard and Ownable for security and basic control.
contract Staking is ReentrancyGuard, Ownable {
    /// @dev Emitted when a user stakes tCORE2 tokens.
    event Staked(address indexed user, uint256 amount, uint256 unlockTime);
    /// @dev Emitted when a user unstakes tCORE2 tokens.
    event Unstaked(address indexed user, uint256 amount);
    /// @dev Emitted when discount parameters are updated.
    event DiscountParamsUpdated(uint256 newMinimum, uint256 newPercent);

    /// @dev Struct to store user staking information.
    struct StakeInfo {
        /// @dev Amount of tCORE2 tokens staked.
        uint256 amount;
        /// @dev Timestamp when the stake can be unlocked.
        uint256 unlockTime;
        /// @dev Whether the user has staked.
        bool hasStaked;
    }

    /// @dev Minimum stake amount required for discount eligibility (3 tCORE2).
    uint256 public minimumStake = 3 * 10**18;
    /// @dev Discount percentage given to eligible stakers (20%).
    uint256 public discountPercent = 20;
    /// @dev Lock period for staked tokens (30 days).
    uint256 public constant LOCK_PERIOD = 30 days;

    /// @dev Mapping to store staking information for each user.
    mapping(address => StakeInfo) public stakes;

    /// @dev Constructor to initialize the contract with an owner.
    /// @param initialOwner The initial owner address.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev Allows users to stake tCORE2 tokens for NFT discount.
    /// @notice Staked tokens will be locked for 30 days.
    function stake() external payable nonReentrant {
        require(msg.value >= minimumStake, "Insufficient stake amount");
        require(!stakes[msg.sender].hasStaked, "Already staked");

        stakes[msg.sender] = StakeInfo({
            amount: msg.value,
            unlockTime: block.timestamp + LOCK_PERIOD,
            hasStaked: true
        });

        emit Staked(msg.sender, msg.value, block.timestamp + LOCK_PERIOD);
    }

    /// @dev Allows users to unstake tCORE2 tokens after lock period expires.
    function unstake() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.hasStaked, "No stake found");
        require(block.timestamp >= userStake.unlockTime, "Stake still locked");

        uint256 amount = userStake.amount;
        
        // Reset user stake info
        delete stakes[msg.sender];

        // Transfer tCORE2 tokens back to user
        payable(msg.sender).transfer(amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @dev Returns the discount percentage for a given user based on their stake.
    /// @param user The address of the user to check.
    /// @return The discount percentage (20% if eligible, 0% otherwise).
    function getDiscountPercentage(address user) external view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (!userStake.hasStaked || userStake.amount < minimumStake) {
            return 0;
        }
        return discountPercent;
    }

    /// @dev Returns the current stake amount for a given user.
    /// @param user The address of the user to check.
    /// @return The current stake amount for the user.
    function getUserStakeAmount(address user) external view returns (uint256) {
        return stakes[user].amount;
    }

    /// @dev Returns the unlock time for a given user's stake.
    /// @param user The address of the user to check.
    /// @return The timestamp when the user can unstake.
    function getUserUnlockTime(address user) external view returns (uint256) {
        return stakes[user].unlockTime;
    }

    /// @dev Checks if a user has staked and is eligible for discount.
    /// @param user The address of the user to check.
    /// @return True if the user has staked and is eligible for discount.
    function isEligibleForDiscount(address user) external view returns (bool) {
        StakeInfo storage userStake = stakes[user];
        return userStake.hasStaked && userStake.amount >= minimumStake;
    }

    /// @dev Allows the owner to update the minimum stake amount.
    /// @param newMinimum The new minimum stake amount in wei.
    function setMinimumStake(uint256 newMinimum) external onlyOwner {
        require(newMinimum > 0, "Minimum must be > 0");
        minimumStake = newMinimum;
        emit DiscountParamsUpdated(newMinimum, discountPercent);
    }

    /// @dev Allows the owner to update the discount percentage.
    /// @param newPercent The new discount percentage (0-100).
    function setDiscountPercent(uint256 newPercent) external onlyOwner {
        require(newPercent <= 100, "Invalid discount percentage");
        discountPercent = newPercent;
        emit DiscountParamsUpdated(minimumStake, newPercent);
    }

    /// @dev Allows the owner to withdraw accumulated fees (if any).
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }

    /// @dev Receive function to accept tCORE2 tokens.
    receive() external payable {
        // This allows the contract to receive tCORE2 tokens
    }
}