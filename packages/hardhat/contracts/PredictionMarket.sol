// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PredictionMarketToken.sol";

contract PredictionMarket is Ownable {
    /////////////////////////
    /// Errors //////////////
    /////////////////////////
    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__InvalidPercentageToLock();
    error PredictionMarket__TokenTransferFailed();
    error PredictionMarket__ETHTransferFailed();
    error PredictionMarket__InsufficientYESReserve();
    error PredictionMarket__InsufficientNOReserve();

    // Checkpoint 5 errors
    error PredictionMarket__PredictionAlreadyReported();
    error PredictionMarket__PredictionNotReported();
    error PredictionMarket__OnlyOracleCanReport();

    // Stubs / future checkpoints
    error PredictionMarket__NotImplementedYet();

    /////////////////////////
    /// Events //////////////
    /////////////////////////
    event MarketReported(address indexed oracle, Outcome winningOutcome, address winningToken);

    /////////////////////////
    /// Enums ///////////////
    /////////////////////////
    enum Outcome {
        YES,
        NO
    }

    /////////////////////////
    /// Constants ///////////
    /////////////////////////
    uint256 public constant PRECISION = 1e18;

    /////////////////////////
    /// State Variables /////
    /////////////////////////
    address public immutable i_oracle;
    uint256 public immutable i_initialTokenValue;
    uint256 public immutable i_initialYesProbability;
    uint256 public immutable i_percentageLocked;

    string public s_question;

    uint256 public s_ethCollateral;
    uint256 public s_lpTradingRevenue;

    PredictionMarketToken public immutable i_yesToken;
    PredictionMarketToken public immutable i_noToken;

    // Checkpoint 5 state
    bool public s_isReported;
    PredictionMarketToken public s_winningToken;

    /////////////////////////
    /// Modifiers ///////////
    /////////////////////////
    modifier predictionNotReported() {
        if (s_isReported) {
            revert PredictionMarket__PredictionAlreadyReported();
        }
        _;
    }

    modifier predictionReported() {
    if (!s_isReported) {
        revert PredictionMarket__PredictionNotReported();
    }
    _;
}


    /////////////////////////
    /// Constructor /////////
    /////////////////////////
    constructor(
        address _liquidityProvider,
        address _oracle,
        string memory _question,
        uint256 _initialTokenValue,
        uint8 _initialYesProbability,
        uint8 _percentageToLock
    ) payable Ownable(_liquidityProvider) {
        /////////////////////////
        /// Checkpoint 2 ////////
        /////////////////////////
        if (msg.value == 0) {
            revert PredictionMarket__MustProvideETHForInitialLiquidity();
        }

        if (_initialYesProbability == 0 || _initialYesProbability >= 100) {
            revert PredictionMarket__InvalidProbability();
        }

        if (_percentageToLock == 0 || _percentageToLock >= 100) {
            revert PredictionMarket__InvalidPercentageToLock();
        }

        i_oracle = _oracle;
        s_question = _question;

        i_initialTokenValue = _initialTokenValue;
        i_initialYesProbability = _initialYesProbability;
        i_percentageLocked = _percentageToLock;

        s_ethCollateral = msg.value;

        /////////////////////////
        /// Checkpoint 3 ////////
        /////////////////////////
        uint256 initialTokenAmount = (msg.value * PRECISION) / _initialTokenValue;

        // Liquidity provider owns initial supply (token logic restriction)
        i_yesToken = new PredictionMarketToken("Yes", "YES", _liquidityProvider, initialTokenAmount);
        i_noToken = new PredictionMarketToken("No", "NO", _liquidityProvider, initialTokenAmount);

        uint256 initialYesAmountLocked =
            (initialTokenAmount * _initialYesProbability * _percentageToLock * 2) / 10000;

        uint256 initialNoAmountLocked =
            (initialTokenAmount * (100 - _initialYesProbability) * _percentageToLock * 2) / 10000;

        bool successYes = i_yesToken.transfer(_liquidityProvider, initialYesAmountLocked);
        bool successNo = i_noToken.transfer(_liquidityProvider, initialNoAmountLocked);

        if (!successYes || !successNo) {
            revert PredictionMarket__TokenTransferFailed();
        }
    }

    /////////////////////////
    /// Checkpoint 4 ////////
    /////////////////////////

    function addLiquidity() external payable onlyOwner predictionNotReported {
        s_ethCollateral += msg.value;

        uint256 tokensAmount = (msg.value * PRECISION) / i_initialTokenValue;

        i_yesToken.mint(address(this), tokensAmount);
        i_noToken.mint(address(this), tokensAmount);
    }

    function removeLiquidity(uint256 _ethToWithdraw) external onlyOwner predictionNotReported {
        uint256 amountTokenToBurn = (_ethToWithdraw * PRECISION) / i_initialTokenValue;

        if (amountTokenToBurn > i_yesToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientYESReserve();
        }

        if (amountTokenToBurn > i_noToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientNOReserve();
        }

        s_ethCollateral -= _ethToWithdraw;

        i_yesToken.burn(address(this), amountTokenToBurn);
        i_noToken.burn(address(this), amountTokenToBurn);

        (bool success,) = msg.sender.call{value: _ethToWithdraw}("");
        if (!success) {
            revert PredictionMarket__ETHTransferFailed();
        }
    }

    /////////////////////////
    /// Checkpoint 5 ////////
    /////////////////////////

    function report(Outcome _winningOutcome) external predictionNotReported {
        if (msg.sender != i_oracle) {
            revert PredictionMarket__OnlyOracleCanReport();
        }

        s_winningToken = _winningOutcome == Outcome.YES ? i_yesToken : i_noToken;
        s_isReported = true;

        emit MarketReported(msg.sender, _winningOutcome, address(s_winningToken));
    }

    ////////////////////////////////
    /// UI Helper (for frontend) ///
    ////////////////////////////////

    /**
     * The UI (already prepared for later checkpoints) indexes the tuple like:
     * [1]=yesOutcome, [2]=noOutcome, [3]=oracle, [4]=tokenValue, [5]=yesReserve, [6]=noReserve,
     * [7]=isReported, [8]=yesToken, [9]=noToken, [10]=winningToken, [11]=ethCollateral,
     * [12]=lpTradingRevenue, [13]=liquidityProvider
     */
    function getPrediction()
        external
        view
        returns (
            string memory question,        // [0]
            string memory yesOutcome,       // [1]
            string memory noOutcome,        // [2]
            address oracle,                // [3]
            uint256 tokenValue,            // [4]
            uint256 yesTokenReserve,       // [5]
            uint256 noTokenReserve,        // [6]
            bool isReported,               // [7]
            address yesToken,              // [8]
            address noToken,               // [9]
            address winningToken,          // [10]
            uint256 ethCollateral,         // [11]
            uint256 lpTradingRevenue,      // [12]
            address liquidityProvider      // [13]
        )
    {
        question = s_question;
        yesOutcome = "Yes";
        noOutcome = "No";
        oracle = i_oracle;

        tokenValue = i_initialTokenValue;

        yesTokenReserve = i_yesToken.balanceOf(address(this));
        noTokenReserve = i_noToken.balanceOf(address(this));

        isReported = s_isReported;
        yesToken = address(i_yesToken);
        noToken = address(i_noToken);
        winningToken = s_isReported ? address(s_winningToken) : address(0);

        ethCollateral = s_ethCollateral;
        lpTradingRevenue = s_lpTradingRevenue;

        liquidityProvider = owner();
    }

    ////////////////////////////////
    /// Future checkpoints stubs ///
    ////////////////////////////////

    function getBuyPriceInEth(uint256 /* optionIndex */, uint256 /* tokenBuyAmount */)
        external
        pure
        returns (uint256)
    {
        // Later checkpoint will implement real pricing
        return 0;
    }

    function getSellPriceInEth(uint256 /* optionIndex */, uint256 /* tokenSellAmount */)
        external
        pure
        returns (uint256)
    {
        // Later checkpoint will implement real pricing
        return 0;
    }

    function buyTokensWithETH(uint256 /* optionIndex */, uint256 /* tokenBuyAmount */)
        external
        payable
    {
        revert PredictionMarket__NotImplementedYet();
    }

    function sellTokensForEth(uint256 /* optionIndex */, uint256 /* tokenSellAmount */)
        external
    {
        revert PredictionMarket__NotImplementedYet();
    }

    function redeemWinningTokens(uint256 /* tokenAmount */) external {
        revert PredictionMarket__NotImplementedYet();
    }

    function resolveMarketAndWithdraw() external {
        revert PredictionMarket__NotImplementedYet();
    }
}
