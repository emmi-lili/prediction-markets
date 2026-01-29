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

        // IMPORTANT: owner = address(this) so this contract can mint/burn later (Checkpoint 4+)
        i_yesToken = new PredictionMarketToken("Yes", "YES", _liquidityProvider, initialTokenAmount);
        i_noToken = new PredictionMarketToken("No", "NO", _liquidityProvider, initialTokenAmount);

        uint256 initialYesAmountLocked = (initialTokenAmount * _initialYesProbability * _percentageToLock * 2) / 10000;

        uint256 initialNoAmountLocked = (initialTokenAmount * (100 - _initialYesProbability) * _percentageToLock * 2) /
            10000;

        bool successYes = i_yesToken.transfer(_liquidityProvider, initialYesAmountLocked);
        bool successNo = i_noToken.transfer(_liquidityProvider, initialNoAmountLocked);

        if (!successYes || !successNo) {
            revert PredictionMarket__TokenTransferFailed();
        }
    }

    /////////////////////////
    /// Checkpoint 4 ////////
    /////////////////////////

    function addLiquidity() external payable onlyOwner {
        // Add ETH collateral
        s_ethCollateral += msg.value;

        // Mint equal amounts of YES/NO tokens to the contract reserve
        uint256 tokensAmount = (msg.value * PRECISION) / i_initialTokenValue;

        i_yesToken.mint(address(this), tokensAmount);
        i_noToken.mint(address(this), tokensAmount);
    }

    function removeLiquidity(uint256 _ethToWithdraw) external onlyOwner {
        // How many tokens correspond to the ETH being removed
        uint256 amountTokenToBurn = (_ethToWithdraw * PRECISION) / i_initialTokenValue;

        // Ensure enough reserves
        if (amountTokenToBurn > i_yesToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientYESReserve();
        }
        if (amountTokenToBurn > i_noToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientNOReserve();
        }

        // Update collateral
        s_ethCollateral -= _ethToWithdraw;

        // Burn token reserves
        i_yesToken.burn(address(this), amountTokenToBurn);
        i_noToken.burn(address(this), amountTokenToBurn);

        // Send ETH back to LP/owner
        (bool success, ) = msg.sender.call{ value: _ethToWithdraw }("");
        if (!success) {
            revert PredictionMarket__ETHTransferFailed();
        }
    }
}
