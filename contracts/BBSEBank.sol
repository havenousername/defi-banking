// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BBSEToken.sol";
import "./ETHBBSEPriceFeedOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";



contract BBSEBank is Ownable {
  // BBSE Token Contract instance
  BBSEToken private bbseTokenContract;

  // ETHBBSEPriceFeedOracle Contract instance
  ETHBBSEPriceFeedOracle private oracleContract;
  
  // Yearly return rate of the bank
  uint32 public yearlyReturnRate;
  
  // Seconds in a year
  uint32 public constant YEAR_SECONDS = 31536000; 

  // Block time in PoS-Ethereum
  uint8 public constant BLOCK_TIME = 12;

  // Average block time (set to large number in order to increase the paid interest in BBSE tokens)
  uint public constant AVG_BLOCK_TIME = 10000000;
  
  // Minimum deposit amount (1 Ether, expressed in Wei)
  uint public constant MIN_DEPOSIT_AMOUNT = 10 ** 18;

  /* Min. Ratio (Collateral value / Loan value)
   * Example: To take a 1 ETH loan,
   * an asset worth of at least 1.5 ETH must be collateralized.
  */
  uint8 public constant COLLATERALIZATION_RATIO = 150;

  // 1% of ever collateral is taken as fee
  uint public constant LOAN_FEE_RATE = 1;

  /* Interest earned per second for a minimum deposit amount.
   * Equals to the yearly return of the minimum deposit amount
   * divided by the number of seconds in a year.
  */
  uint public interestPerSecondForMinDeposit;

  /* The value of the total deposited ETH.
   * BBSEBank shouldn't be giving loans when requested amount + totalDepositAmount > contract's ETH balance.
   * E.g., if all depositors want to withdraw while no borrowers paid their loan back, then the bank contract
   * should still be able to pay.
  */
  uint public totalDepositAmount;

  // Represents an investor record
  struct Investor {
    uint256 amount;
    bool hasActiveDeposit;
    uint256 startTime;
  }

  // Address to investor mapping
  mapping (address => Investor) public investors;

  // Represents a borrowed record
  struct Borrower {
    bool hasActiveLoan;
    uint256 amount;
    uint256 collateral;
  }

  // Address to borrower mapping
  mapping(address  => Borrower) public borrowers;

  /**
  * @dev Check whether the yearlyReturnRate value is between 1 and 100
  */
  modifier validRate(uint _rate) {
    require(_rate > 0 && _rate <= 100,  "Yearly return rate must be between 1 and 100");
    _;
  }

  /**
  * @dev Initializes the bbseTokenContract with the provided contract address.
  * Sets the yearly return rate for the bank.
  * Yearly return rate must be between 1 and 100.
  * Calculates and sets the interest earned per second for a minumum deposit amount
  * based on the yearly return rate.
  * @param _bbseTokenContract address of the deployed BBSEToken contract
  * @param _yearlyReturnRate yearly return rate of the bank
  * @param _oracleContract address of the deployed ETHBBSEPriceFeedOracle contract
  */
  constructor (address _bbseTokenContract, uint32 _yearlyReturnRate, address _oracleContract) public validRate(_yearlyReturnRate) {
    bbseTokenContract = BBSEToken(_bbseTokenContract);
    oracleContract = ETHBBSEPriceFeedOracle(_oracleContract);

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

    // update deposit amount
    totalDepositAmount += msg.value;
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
    uint depositDuration = (block.number - investor.startTime) * AVG_BLOCK_TIME;

    // update deposit amount
    totalDepositAmount -= depositedAmount;

    uint interestPerSecond = interestPerSecondForMinDeposit * (depositedAmount / MIN_DEPOSIT_AMOUNT);
    uint interest = interestPerSecond * depositDuration;

    // reset investor object
    investor.startTime = 0;
    investor.hasActiveDeposit = false;
    investor.amount = 0;

    payable(msg.sender).transfer(depositedAmount);

    bbseTokenContract.mint(msg.sender, interest);
  }

  /**
  * @dev Updates the value of the yearly return rate.
  * Only callable by the owner of the BBSEBank contract.
  * @param _yearlyReturnRate new yearly return rate
  */
  function updateYearlyReturnRate(uint32 _yearlyReturnRate) public onlyOwner validRate(_yearlyReturnRate) {
    yearlyReturnRate = _yearlyReturnRate;
  }

  /**
  * @dev Collateralize BBSE Token to borrow ETH.
  * A borrower can't have more than one active loan.
  * ETH amount to be borrowed + totalDepositAmount, must be existing in the contract balance.
  * @param amount the amount of ETH loan request (expressed in Wei)
  */
  function borrow(uint amount) public {
    require(!borrowers[msg.sender].hasActiveLoan, "Account can't have multiple active loans");
    string memory totalDepositAmountS = Strings.toString(totalDepositAmount);
    string memory amountS = Strings.toString(amount);

    require(amount + totalDepositAmount <= address(this).balance , "The bank can't lend this amount right now");

    // Get the latest price feed rate for ETH/BBSE from the price feed oracle
    uint priceFeedRate = oracleContract.getRate();
    uint collateral = (amount * COLLATERALIZATION_RATIO * priceFeedRate) / 100;

    /* Try to transfer BBSE tokens from msg.sender (i.e. borrower) to BBSEBank.
    *  msg.sender must set an allowance to BBSEBank first, since BBSEBank
    *  needs to transfer the tokens from msg.sender to itself
    */
    require(bbseTokenContract.transferFrom(msg.sender, address(this), collateral), "BBSEBank can't receive your tokens");
    borrowers[msg.sender] = Borrower(true, amount, collateral);

    payable(msg.sender).transfer(amount);
  }

  /**
 * @dev Pays the borrowed loan.
  * Borrower receives back the collateral - fee BBSE tokens.
  * Borrower must have an active loan.
  * Borrower must send the exact ETH amount borrowed.
  */
  function payLoan() public payable {
    Borrower storage borrower = borrowers[msg.sender];
    require(borrower.hasActiveLoan, "Account must have an active loan to pay back");
    require(msg.value == borrower.amount, "The paid amount must match the borrowed amount");

    uint fee = (borrowers[msg.sender].collateral * LOAN_FEE_RATE) / 100;
    totalDepositAmount += fee;
    totalDepositAmount -= borrowers[msg.sender].collateral;

    bbseTokenContract.transfer(msg.sender, borrowers[msg.sender].collateral - fee);


    borrower.collateral = 0;
    borrower.amount = 0;
    borrower.hasActiveLoan = false;
  }

  /**
  * @dev Called every time Ether is sent to the contract.
  * Required to fund the contract.
  */
  receive() external payable {}
}
