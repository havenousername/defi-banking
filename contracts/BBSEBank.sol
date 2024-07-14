// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BBSEToken.sol";

contract BBSEBank {
  // BBSE Token Contract instance
  BBSEToken private bbseTokenContract;
  
  // Yearly return rate of the bank
  uint32 public yearlyReturnRate;
  
  // Seconds in a year
  uint32 public constant YEAR_SECONDS = 31536000; 

  // Block time in PoS-Ethereum
  uint8 public constant BLOCK_TIME = 12;
  
  // Minimum deposit amount (1 Ether, expressed in Wei)
  uint public constant MIN_DEPOSIT_AMOUNT = 1_000_000_000_000_000_000;

  /* Interest earned per second for a minimum deposit amount.
   * Equals to the yearly return of the minimum deposit amount
   * divided by the number of seconds in a year.
  */
  uint public interestPerSecondForMinDeposit;

  // Represents an investor record
  struct Investor {
    uint256 amount;
    bool hasActiveDeposit;
    uint256 startTime;
  }

  // Address to investor mapping
  mapping (address => Investor) public investors;

  /**
  * @dev Initializes the bbseTokenContract with the provided contract address.
  * Sets the yearly return rate for the bank.
  * Yearly return rate must be between 1 and 100.
  * Calculates and sets the interest earned per second for a minumum deposit amount
  * based on the yearly return rate.
  * @param _bbseTokenContract address of the deployed BBSEToken contract
  * @param _yearlyReturnRate yearly return rate of the bank
  */
  constructor (address _bbseTokenContract, uint32 _yearlyReturnRate) public {
    bbseTokenContract = BBSEToken(_bbseTokenContract);

    require(_yearlyReturnRate <= 100 && _yearlyReturnRate >= 1, "Yearly return rate must be between 1 and 100");
    yearlyReturnRate = _yearlyReturnRate;

    interestPerSecondForMinDeposit = ((MIN_DEPOSIT_AMOUNT * yearlyReturnRate) / 100) / YEAR_SECONDS;
  }

  /**
  * @dev Initializes the respective investor object in investors mapping for the caller of the function.
  * Sets the amount to message value and starts the deposit time (hint: use block number as the start time).
  * Minimum deposit amount is 1 Ether (be careful about decimals!)
  * Investor can't have an already active deposit.
  */
  function deposit() payable public {
    require(msg.value >= MIN_DEPOSIT_AMOUNT, "Minimum deposit amount is 1 Ether");
    Investor storage investor = investors[msg.sender];
    require(!investor.hasActiveDeposit, "Account can\'t have multiple active deposits");
    investors[msg.sender] = Investor(msg.value, true, block.number);
  }

  /**
  * @dev Calculates the interest to be paid out based
  * on the deposit amount and duration.
  * Transfers back the deposited amount in Ether.
  * Mints BBSE tokens to investor to pay the interest (1 token = 1 interest).
  * Resets the respective investor object in investors mapping.
  * Investor must have an active deposit.
  */
  function withdraw() public {
    Investor storage investor = investors[msg.sender];
    require(investor.hasActiveDeposit, "Account must have an active deposit to withdraw");

    uint depositedAmount = investor.amount;
    uint depositDuration = (block.number - investor.startTime) * BLOCK_TIME;

    uint interestPerSecond = interestPerSecondForMinDeposit * (depositedAmount / MIN_DEPOSIT_AMOUNT);
    uint interest = interestPerSecond * depositDuration;


    investor.startTime = 0;
    investor.hasActiveDeposit = false;
    investor.amount = 0;

    payable(msg.sender).transfer(depositedAmount);

    bbseTokenContract.mint(msg.sender, interest);
  }
}
