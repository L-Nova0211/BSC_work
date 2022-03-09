// SPDX-License-Identifier: MIT
// File: contracts/libs/BEP20.sol

pragma solidity = 0.6.12;

/**
 *Submitted for verification at BscScan.com on 2021-10-20
*/

/*
	RobustSwap by the Robust Protocol team
	Website: https://robustprotocol.fi
	Telegram: https://t.me/robustprotocol
	Twitter: https://twitter.com/robustprotocol
	Medium: https://robustprotocol.medium.com
	GitBook: https://docs.robustprotocol.fi
	GitHub: https://github.com/robustprotocol
	Reddit: https://www.reddit.com/r/robustProtocol
*/

// File: contracts/RobustSwap.sol
import 'BEP20.sol';

contract RobustSwap is BEP20 {

	using Address for address;

	// The operator can perform all updates except minting
	address public operator;

	// Operator timelock
	bool public operatorTimeLocked = false;

	// Timelock contract
	address public operatorTimelockContract;

	// Max tax rate in basis points (Default: 20% of transaction amount)
	uint16 private constant MAXIMUM_TAX_RATE = 2000;
	
	// Transfer Tax
	bool public transferTaxEnabled = true;

	// Buy tax rate in basis points (Default: 6% of transaction amount)
	uint16 public transferTaxRateBuy = 600;

	// Sell tax rate in basis points (Default: 8% of transaction amount)
	uint16 public transferTaxRateSell = 800;

	// Max burn tax rate (Default: 100% of tax amount)
	uint16 private constant MAXIMUM_BURN_RATE = 100;

	// Burn address
	address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;	

	// Buy burn rate (Default: 0 of transferTaxRateBuy)
	uint16 public burnRateBuy = 0;

	// Sell burn rate (Default: 0 of transferTaxRateSell)
	uint16 public burnRateSell = 0;

	// Max supply of RobustSwap RBS
	uint256 public constant MAXIMUM_SUPPLY = 106050 ether;

	// Keep track of how many tokens have been minted
	uint256 public mintedSupply;

	// Keep track of total amount of tokens taxed
	uint256 public mintedTaxed;

	// Min tax transfer limit rate in basis points (Default: 0.1% of the total supply)
	uint16 private constant MINIMUM_TRANSFER_LIMIT = 10;

	// Transfer limit rate in basis points (Default: 1% of the total supply)
	uint16 public transferAmountLimitRate = 100;

	// Auto trigger for autoLiquidity and autoSell
	bool public autoTrigger = true;

	// Auto trigger in progress
	bool private _inAutoTrigger;

	// BNB for autoTrigger to occur in basis points (Default: 1 BNB)
	uint256 public autoTriggerAmount = 1 ether;

	// Min BNB for autoTrigger to occur in basis points (Default: 10% of autoTriggerAmount, 0.1 BNB)
	uint16 public autoTriggerAmountRate = 1000;

	// Auto liquidity generation
	bool public autoLiquidityEnabled = true;

	// Auto sell RBS for BNB
	bool public autoSellEnabled = true;

	// Modifiable: Router will be changed when RobustSwap AMM is released
	IUniswapV2Router02 private _robustSwapRouter;

	// The trading pair
	address public robustSwapBNBPair;

	// Addresses excluded from taxes
	mapping(address=> bool) private _taxExcludedList;

	// Addresses excluded from transfer limit
	mapping(address=> bool) private _transferLimitExcluded;

	// LP Pairs excluded from taxes
	mapping(address=> bool) private _robustSwapPairLPList;

	// Enable trading. This can only occur once
	bool private _tradingEnabled = false;

	// Prevent bot transactions
	mapping (address => uint256) private _botGuard;

	// Max bot guard blocks (Default: 10 Blocks)
	uint8 private constant MAXIMUM_BOTGUARD_BLOCKS = 10;

	// Bot guard blocks (Default: 5 Blocks)
	uint8 public botGuardBlocks = 5;

	// Events are necessary to keep track of all updates and changes especially by the operator
	event OperatorSet(address indexed previousOperator, address indexed newOperator);
	event UpdateOperatorSetTimeLock(address indexed previousOperator, address indexed timeLockedOperator, bool operatorTimeLocked);
	event MintRBS(address indexed owner, address indexed recipient, uint256 amountMinted, uint256 MintedSupply);
	event AutoLiquidityRBS(uint256 amountRBS, uint256 amountBNB);
	event AutoLiquidityBNB(uint256 amountRBS, uint256 amountBNB);
	event AutoSell(uint256 balanceRBS, uint256 soldRBS);
	event EnableTrading(address indexed operator, uint256 timeEnabled);
	event UpdateTransferTaxEnabled(address indexed operator, bool enabled);
	event UpdateRateTax(address indexed operator, uint16 previousBuyTaxRate, uint16 newBuyTaxRate, uint16 previousSellTaxRate, uint16 newSellTaxRate);
	event UpdateRateBurn(address indexed operator, uint16 previousBuyBurnRate, uint16 newBuyBurnRate, uint16 previousSellBurnRate, uint16 newSellBurnRate);
	event UpdateRateTransferLimit(address indexed operator, uint16 previousRate, uint16 newRate);
	event UpdateAutoLiquidityStatus(address indexed operator, bool enabled);
	event UpdateTransferLimitExclusionRemove(address indexed operator, address indexed removedAddress);
	event UpdateTransferLimitExclusionAdd(address indexed operator, address indexed addedAddress);
	event UpdateTaxExclusionAdd(address indexed operator, address indexed addedAddress);
	event UpdateTaxExclusionRemove(address indexed operator, address indexed removedAddress);	
	event UpdatePairListRemove(address indexed operator, address indexed removedLPPair);
	event UpdatePairListAdd(address indexed operator, address indexed addedLPPair);		
	event UpdateBotGuard(address indexed operator, uint8 previousBlocksLock, uint8 newBlocksLock);
	event UpdateAutoTrigger(address indexed operator, bool previousTrigger, bool newTrigger, uint256 previousAmount, uint256 newAmount, uint16 previousRate, uint16 newRate);
	event UpdateAutoSellEnabled(address indexed operator, bool enabled);
	event UpdateRobustSwapRouter(address indexed operator, address indexed router, address indexed pair);
	event BalanceBurnRBS(address indexed operator, uint256 burnedAmount);	
	event BalanceWithdrawToken(address indexed operator, address indexed tokenAddress, uint256 amountTokenTransfered);
	event SwapRBSForBNB(uint256 amountIn, address[] path);
	event AddLiquidity(uint256 addedTokenAmount, uint256 addedBNBAmount);	
	event TransferTaxed(address indexed sender, address indexed recipient, uint256 amountTransaction, uint256 amountSent, uint256 amountTaxed, uint256 amountBurned, uint256 amountLiquidity);
	event TransferNotTaxed(address indexed sender, address indexed recipient, uint256 amountTransaction, bool isAddressTaxExcluded);

	/**
	* @notice onlyOperator functions can be performed by the operator
	* Operator can perform all update functions
	* Timelock the operator with updateOperatorSetTimeLock
	*/
	modifier onlyOperator() {
		require(operator == msg.sender, "RobustSwap::onlyOperator:Caller is not the operator");
		_;
	}

	/**
	* @notice timelockedOperator functions can be performed only after the operator is timelocked
	* balanceWithdrawToken, balanceBurnRBS, updateOperatorSetPending
	*/
	modifier timelockedOperator() {
		require(operatorTimeLocked, "RobustSwap::timelockedOperator:Operator needs to be timelocked");
		_;
	}

	/**
	* @notice Transfer amount limitation
	*/
	modifier transferAmountLimit(address sender, address recipient, uint256 amount) {
		
		if (maxTransferLimitAmount() > 0) {

			if (
				!isTransferLimitExcluded(sender)
				&& !isTransferLimitExcluded(recipient)
			) {
				require(amount <= maxTransferLimitAmount(), "RobustSwap::transferAmountLimit:Transfer amount exceeds the maxTransferAmount");
			}
		}
		_;
	}

	/**
	* @notice autoliquidity, autoSell
	*/	
	modifier autoTriggerLock {
		_inAutoTrigger = true;
		_;
		_inAutoTrigger = false;
	}

	/**
	* @notice Transfer tax exemption
	*/
	modifier noTransferTax {
		bool _transferTaxEnabled = transferTaxEnabled;
		transferTaxEnabled = false;
		_;
		transferTaxEnabled = _transferTaxEnabled;
	}

	/**
	* @notice Constructs the RobustSwap (RBS) contract
	*/
	constructor(address _operatorTimelockContract) public BEP20() {
		require(_operatorTimelockContract != address(0), "RobustSwap::constructor:Timelock cannot be the zero address");

		// Set initial operator
		operator = msg.sender;
		emit OperatorSet(address(0), operator);

		// The timelock contract address
		operatorTimelockContract = _operatorTimelockContract;

		// Set initial transfer limit exemptions
		_transferLimitExcluded[address(this)] = true;
		_transferLimitExcluded[msg.sender] = true;
		_transferLimitExcluded[address(0)] = true;
		_transferLimitExcluded[BURN_ADDRESS] = true;

		// Set initial transfer tax exemptions
		_taxExcludedList[address(this)] = true;
		_taxExcludedList[msg.sender] = true;
		_taxExcludedList[address(0)] = true;
		_taxExcludedList[BURN_ADDRESS] = true;
	}

	/**
	* @notice Creates '_amount' token to '_recipient'
	* Must only be called by the owner (MasterChef)
	* No more RBS minting after the maximum supply is minted
	*/
	function mint(address _recipient, uint256 _amount) external onlyOwner {
		require(_amount <= mintedBalance(), "RobustSwap::mint:Maximum supply minted");
		require(_recipient != address(0),"RobustSwap::mint:Zero address.");
		require(_amount > 0,"RobustSwap::mint:Zero amount");
		mintedSupply = mintedSupply.add(_amount);
		emit MintRBS(msg.sender, _recipient, _amount, mintedSupply);
		_mint(_recipient, _amount);
	}

	/**
	* @dev Overrides transfer function to meet tokenomics of RobustSwap (RBS)
	*/
	function _transfer(address sender, address recipient, uint256 amount) internal virtual override transferAmountLimit(sender, recipient, amount) {
		// Manually excluded adresses from transaction tax
		bool isAddressTaxExcluded = (isTaxExcluded(sender) || isTaxExcluded(recipient));

		// autoLiquidity, autoSell
		if (autoTrigger && !_inAutoTrigger
			&& isTradingEnabled()
			&& routerAddress() != address(0)
			&& robustSwapBNBPair != address(0)
			&& !isRobustSwapPair(sender)
			&& !isTaxExcluded(sender)) {

					if (autoLiquidityEnabled)
						autoLiquidity();

					if (autoSellEnabled)
						autoSell();
		}

		// Tax free transfers
		if (amount == 0 || !transferTaxEnabled || isAddressTaxExcluded) {

			emit TransferNotTaxed(sender, recipient, amount, isAddressTaxExcluded);

			if (recipient == BURN_ADDRESS) {
					// Burn tokens sent to burn address
					if (amount > 0)
						_burn(sender, amount);

			} else {
				// Tax free transfer
				super._transfer(sender, recipient, amount);
			}

		} else {
				// Trading needs to be enabled. Once enabled, trading cannot be disabled
				require(isTradingEnabled(), "RobustSwap::_transfer:Trading is not yet enabled");

				//Transfer can only occur afer number of botGuardBlocks
				require(_botGuard[tx.origin] <= block.number,"RobustSwap::_transfer:Transfer only after number of botGuardBlocks");

				// Taxed transfers
				taxedTransfers(sender, recipient, amount);
		}
	}

	/**
	* @dev Process taxed transfers
	*/
	function taxedTransfers(address sender, address recipient, uint256 amount) private {

			// Tax rate
			uint16 rateTax = 0;

			// Burn rate
			uint16 rateBurn = 0;

			// Burn amount
			uint256 burnAmount = 0;

			// Liquidity amount
			uint256 liquidityAmount = 0;

			// Tax amount
			uint256 taxAmount = 0;

			// Send amount
			uint256 sendAmount = 0;

			// Buy Transfer
			if (isRobustSwapPair(sender)) {

				// Set buy tax and burn rates
				rateTax = transferTaxRateBuy;
				rateBurn = burnRateBuy;
			}

			// Sell Transfer
			if (isRobustSwapPair(recipient)) {

				// Set sell tax and burn rates
				rateTax = transferTaxRateSell;
				rateBurn = burnRateSell;
			}

			// Calculate applicable tax from amount
			if (rateTax > 0)
				taxAmount = amount.mul(rateTax).div(10000);

			// Calculate applicable burn from tax
			if (rateBurn > 0 && rateTax != 0)
				burnAmount = taxAmount.mul(rateBurn).div(100);

			// Amount for liquidity
			liquidityAmount = taxAmount.sub(burnAmount);

			// Amount sent to recipient
			sendAmount = amount.sub(taxAmount);

			//Set new botGuard
			_botGuard[tx.origin] = block.number.add(botGuardBlocks);

			if (rateTax > 0) {
				emit TransferTaxed(sender, recipient, amount, sendAmount, taxAmount, burnAmount, liquidityAmount);

			} else {
				emit TransferNotTaxed(sender, recipient, amount, false);

			}

			// Burn amount from transaction
			if (burnAmount > 0)
				_burn(sender, burnAmount);

			// Transfer liquidity amount to contract
			if (liquidityAmount > 0) {
				mintedTaxed = mintedTaxed.add(liquidityAmount);
				super._transfer(sender, address(this), liquidityAmount);
			}

			// Transfer to recipient
			super._transfer(sender, recipient, sendAmount);
	}

	/**
	* @dev Auto generate RBS-BNB liquidity
	*/
	function autoLiquidity() private autoTriggerLock noTransferTax {
		// Use RBS balance for liquidity
		uint256 runningBalanceRBS = balanceOf(address(this));		
		uint256 runningBalanceBNB = address(this).balance;	
		uint totalLiquidityAmount = getTotalLiquidityAmount(runningBalanceRBS);

		// Check for sufficient balances
		if(totalLiquidityAmount != 0 && runningBalanceRBS >= totalLiquidityAmount.mul(2)) {

			// Swap RBS for BNB
			swapRBSForBNB(totalLiquidityAmount);

			// Get BNB amount received from swap
			uint256 liquidityBNB = address(this).balance.sub(runningBalanceBNB);

			emit AutoLiquidityRBS(totalLiquidityAmount, liquidityBNB);

			// Add liquidity
			addLiquidity(totalLiquidityAmount, liquidityBNB);

		}

		// Use BNB balance for liquidity
		runningBalanceBNB = address(this).balance;
		runningBalanceRBS = balanceOf(address(this));
		totalLiquidityAmount = getTotalLiquidityAmount(runningBalanceRBS);
		uint256 minTriggerAmount = minAutoTriggerAmount();

		// Check for sufficient balances
		if(totalLiquidityAmount != 0 && runningBalanceRBS >= totalLiquidityAmount && runningBalanceBNB >= minTriggerAmount) {

			emit AutoLiquidityBNB(totalLiquidityAmount, minTriggerAmount);

			// Add liquidity
			addLiquidity(totalLiquidityAmount, minTriggerAmount);
		}
	}

	/**
	* @dev Auto sell contract RBS balance for BNB
	*/
	function autoSell() private autoTriggerLock noTransferTax {
		uint256 runningBalanceRBS = balanceOf(address(this));

		// Get RBS amount to sell
		uint totalSellAmount = getTotalLiquidityAmount(runningBalanceRBS);

		if (totalSellAmount != 0 && runningBalanceRBS >= totalSellAmount) {
			
			emit AutoSell(runningBalanceRBS, totalSellAmount);
			
			// Sell RBS
			swapRBSForBNB(totalSellAmount);
		}
	}

	/**
	* @dev Swap RBS for BNB
	*/
	function swapRBSForBNB(uint256 amountRBS) private {
		// Generate the robustSwap pair path of token -> WBNB
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = _robustSwapRouter.WETH();

		_approve(address(this), address(_robustSwapRouter), amountRBS);

		// Execute the swap
		_robustSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
			amountRBS,
			0, // Accept any amount of BNB
			path,
			address(this),
			block.timestamp
		);

		emit SwapRBSForBNB(amountRBS, path);
	}

	/**
	* @dev Add RBS-BNB liquidity
	*/
	function addLiquidity(uint256 amountRBS, uint256 amountBNB) private {
		// Approve token transfer to cover all possible scenarios
		_approve(address(this), address(_robustSwapRouter), amountRBS);

		// Add the liquidity
		_robustSwapRouter.addLiquidityETH{value: amountBNB}(
			address(this),
			amountRBS,
			0, // slippage is unavoidable
			0, // slippage is unavoidable
			address(this),
			block.timestamp
		);
		
		emit AddLiquidity(amountRBS, amountBNB);
	}

	/**
	* @dev Calculate the amount of RBS required for autoLiquidity and autoSell
	*/
	function getTotalLiquidityAmount(uint256 runningBalanceRBS) private view returns(uint)  {
		require(runningBalanceRBS > 0,"RobustSwap::getTotalLiquidityAmount:Invalid runningBalanceRBS");
		uint quoteOutputBNB = quotePriceRBS(runningBalanceRBS);

		if (quoteOutputBNB !=0 && quoteOutputBNB >= autoTriggerAmount) {

			// Calculate RBS price based on the RBS-BNB reserve
			uint amountRBSPerBNB = runningBalanceRBS.div(quoteOutputBNB);

			// Calculate amount of required RBS
			uint totalLiquidityAmount = amountRBSPerBNB.mul(minAutoTriggerAmount());

			return totalLiquidityAmount;

		} else {
			
			return 0;
		}
	}

	/**
	* @dev Calculate RBS price based on RBS-BNB reserve
	* Required for autoLiquidity and autoSell
	*/
	function quotePriceRBS(uint _amountRBS) private view returns(uint) {
		require(robustSwapBNBPair != address(0), "RobustSwap::quotePriceRBS:Invalid pair address.");
		require(_amountRBS > 0,"RobustSwap::quotePriceRBS:Invalid input amount");

		IUniswapV2Pair pair = IUniswapV2Pair(robustSwapBNBPair);
		(uint Reserve0, uint Reserve1,) = pair.getReserves();

		//  BNB/RBS LP Pair
		IBEP20 token0 = IBEP20(pair.token0());
		IBEP20 token1 = IBEP20(pair.token1());

		// Check if reserve has funds
		if (Reserve0 > 0 && Reserve1 > 0) {
			if (address(token0) == address(this))
				return (_amountRBS.mul(Reserve1)).div(Reserve0);

			if (address(token1) == address(this))
				return (_amountRBS.mul(Reserve0)).div(Reserve1);
		}else{
			// No funds in reserve
			return 0;
		}
	}

	/**
	* @dev Returns the the trading enabled status
	*/
	function isTradingEnabled() public view returns (bool) {
		return _tradingEnabled;
	}

	/**
	* @dev Returns total number of burned tokens
	*/
	function mintedBurned() external view returns (uint256) {
		return mintedSupply.sub(totalSupply());
	}

	/**
	* @dev Returns the max transfer limit amount
	*/
	function maxTransferLimitAmount() public view returns (uint256) {
		return totalSupply().mul(transferAmountLimitRate).div(10000);
	}

	/**
	* @dev Returns the min BNB autoTrigger amount
	*/
	function minAutoTriggerAmount() public view returns (uint256) {
		return autoTriggerAmount.mul(autoTriggerAmountRate).div(10000);
	}

	/**
	* @dev Returns transfer limit status for an address
	*/
	function isTransferLimitExcluded(address _transferLimitExemption) public view returns (bool) {
		return _transferLimitExcluded[_transferLimitExemption];
	}

	/**
	* @dev Returns tax status for an address
	*/
	function isTaxExcluded(address _taxExcluded) public view returns (bool) {		
		return _taxExcludedList[_taxExcluded];
	}

	/**
	* @dev Returns if an address is added to the RobustSwap LP list
	*/
	function isRobustSwapPair(address _RobustSwapPair) public view returns (bool) {		
		return _robustSwapPairLPList[_RobustSwapPair];
	}

	/**
	* @dev Returns the total of unminted RBS
	*/
	function mintedBalance() public view returns (uint256) {
		return MAXIMUM_SUPPLY.sub(mintedSupply);
	}

	/**
	* @dev Returns the current RobustSwap router address
	*/
	function routerAddress() public view returns (address) {
		return address(_robustSwapRouter);
	}

	/**
	* @dev Receive BNB from robustSwapRouter when swapping
	*/
	receive() external payable {}

	/**
	* @dev The operator wields an enormous amount of powers
	* Set the operator to the Robust timelock contract
	* This can be set only once
	*/
	function updateOperatorSetTimeLock() external onlyOperator {
		require(!operatorTimeLocked, "RobustSwap::updateOperatorSetTimeLock:Timelock is already enabled");
		operatorTimeLocked = true;
		emit UpdateOperatorSetTimeLock(operator, operatorTimelockContract, operatorTimeLocked);
		operator = operatorTimelockContract;
	}

	/**
	* @dev Enable trading. This can only occur once
	* After enabled, trading cannot be disabled
	* Can only be called by the current operator
	*/
	function enableTrading() external onlyOperator {
		require(!_tradingEnabled, "RobustSwap::enableTrading:Trading is already enabled");
		require(routerAddress() != address(0), "RobustSwap::enableTrading:Router address is not set");
		require(robustSwapBNBPair != address(0), "RobustSwap::enableTrading:RBS-BNB pair not found");
		emit EnableTrading(operator, block.timestamp);
		_tradingEnabled = true;
	}

	/**
	* @dev Update transfer tax enabled status
	* Can only be called by the current operator
	*/
	function updateTransferTaxEnabled(bool _transferTaxEnabled) external onlyOperator {
		if (!_transferTaxEnabled)
			require(transferTaxEnabled,"RobustSwap::updateTransferTaxEnabled:transferTaxEnabled is disabled");		
		if (_transferTaxEnabled)
			require(!transferTaxEnabled,"RobustSwap::updateTransferTaxEnabled:transferTaxEnabled is enabled");
		emit UpdateTransferTaxEnabled(operator, _transferTaxEnabled);		
		transferTaxEnabled = _transferTaxEnabled;
	}

	/**
	* @dev Update transaction tax rates (buy, sell and transfer)
	* Setting rate to 0 disables transaction tax
	* Can only be called by the current operator
	*/
	function updateRateTax(uint16 _transferTaxRateBuy, uint16 _transferTaxRateSell) external onlyOperator {
		require(_transferTaxRateBuy <= MAXIMUM_TAX_RATE, "RobustSwap::updateRateTax:Buy transfer tax rate must not exceed the maximum rate");
		require(_transferTaxRateSell <= MAXIMUM_TAX_RATE, "RobustSwap::updateRateTax:Sell transfer tax rate must not exceed the maximum rate");
		emit UpdateRateTax(operator, transferTaxRateBuy, _transferTaxRateBuy, transferTaxRateSell, _transferTaxRateSell);
		if(_transferTaxRateBuy != transferTaxRateBuy)
			transferTaxRateBuy = _transferTaxRateBuy;		
		if(_transferTaxRateSell != transferTaxRateSell)
			transferTaxRateSell = _transferTaxRateSell;		
	}

	/**
	* @dev Update transaction tax burn rates
	* Setting rate to 0 disables burn rate
	* Disabled - All tax sent to the RBS contract for autoLiquidity and autoSell
	* Can only be called by the current operator
	*/
	function updateRateBurn(uint16 _burnRateBuy, uint16 _burnRateSell) external onlyOperator {
		require(_burnRateBuy <= MAXIMUM_BURN_RATE, "RobustSwap::updateRateBurn:Buy burn rate must not exceed the maximum rate");
		require(_burnRateSell <= MAXIMUM_BURN_RATE, "RobustSwap::updateRateBurn:Sell burn rate must not exceed the maximum rate");
		emit UpdateRateBurn(operator, burnRateBuy, _burnRateBuy, burnRateSell, _burnRateSell);
		if(_burnRateBuy != burnRateBuy)
			burnRateBuy = _burnRateBuy;
		if(_burnRateSell != burnRateSell)
			burnRateSell = _burnRateSell;
	}

	/**
	* @dev Update the single transfer amount limit rate
	* Transfer limit works with the total supply of RBS
	* Setting rate to 0 or 10000 and above will disable this feature
	* Can only be called by the current operator
	*/
	function updateRateTransferLimit(uint16 _transferAmountLimitRate) external onlyOperator {
		if (_transferAmountLimitRate < MINIMUM_TRANSFER_LIMIT || _transferAmountLimitRate >= 10000)
			_transferAmountLimitRate = 0;
		emit UpdateRateTransferLimit(operator, transferAmountLimitRate, _transferAmountLimitRate);
		if(_transferAmountLimitRate != transferAmountLimitRate)
			transferAmountLimitRate = _transferAmountLimitRate;
	}

	/**
	* @dev Add address exempted from transfer amount limit (eg. CEX, MasterChef)
	* Can only be called by the current operator
	*/
	function updateTransferLimitExclusionAdd(address _addTransferLimitExclusion) external onlyOperator {
		require(_addTransferLimitExclusion != address(0),"RobustSwap::updateTransferLimitExclusionAdd:Zero address");
		require(!isTransferLimitExcluded(_addTransferLimitExclusion),"RobustSwap::updateTransferLimitExclusionAdd:Address already excluded from transfer amount limit");
		emit UpdateTransferLimitExclusionAdd(operator, _addTransferLimitExclusion);
		_transferLimitExcluded[_addTransferLimitExclusion] = true;
	}

	/**
	* @dev Remove address exempted from transfer amount limit
	* Can only be called by the current operator
	*/
	function updateTransferLimitExclusionRemove(address _removeTransferLimitExclusion) external onlyOperator {
		require(_removeTransferLimitExclusion != address(0),"RobustSwap::updateTransferLimitExclusionRemove:Zero address");
		require(isTransferLimitExcluded(_removeTransferLimitExclusion),"RobustSwap::updateTransferLimitExclusionRemove:Address not excluded from transfer amount limit");		
		emit UpdateTransferLimitExclusionRemove(operator, _removeTransferLimitExclusion);		
		_transferLimitExcluded[_removeTransferLimitExclusion] = false;
	}

	/**
	* @dev Add address exempted from transfer tax (eg. CEX, MasterChef)
	* Can only be called by the current operator
	*/
	function updateTaxExclusionAdd(address _addTaxExclusion) external onlyOperator {
		require(_addTaxExclusion != address(0),"RobustSwap::updateTaxExclusionAdd:Zero address");
		require(!isTaxExcluded(_addTaxExclusion),"RobustSwap::updateTaxExclusionAdd:Address is already excluded from transfer tax");		
		emit UpdateTaxExclusionAdd(operator, _addTaxExclusion);		
		_taxExcludedList[_addTaxExclusion] = true;
	}

	/**
	* @dev Remove address exempted from transfer tax
	* Can only be called by the current operator
	*/
	function updateTaxExclusionRemove(address _removeTaxExclusion) external onlyOperator {
		require(_removeTaxExclusion != address(0),"RobustSwap::updateTaxExclusionRemove:Zero address");
		require(isTaxExcluded(_removeTaxExclusion),"RobustSwap::updateTaxExclusionRemove:Address is not excluded from transfer tax");	
		emit UpdateTaxExclusionRemove(operator, _removeTaxExclusion);
		_taxExcludedList[_removeTaxExclusion] = false;
	}

	/**
	* @dev Add LP address to the RobustSwap pair list
	* Used to determine if a transaction is buy, sell or transfer for applicable tax
	* Can only be called by the current operator
	*/
	function updatePairListAdd(address _addRobustSwapPair) external onlyOperator {
		require(_addRobustSwapPair != address(0),"RobustSwap::updatePairListAdd:Zero address");
		require(!isRobustSwapPair(_addRobustSwapPair),"RobustSwap::updatePairListAdd:LP address already included");		
		emit UpdatePairListAdd(operator, _addRobustSwapPair);		
		_robustSwapPairLPList[_addRobustSwapPair] = true;
	}

	/**
	* @dev Remove LP address from the RobustSwap pair list
	* Used to determine if a transaction is buy, sell or transfer for applicable tax
	* Can only be called by the current operator
	*/
	function updatePairListRemove(address _removeRobustSwapPair) external onlyOperator {
		require(_removeRobustSwapPair != address(0),"RobustSwap::updatePairListRemove:Zero address");
		require(isRobustSwapPair(_removeRobustSwapPair),"RobustSwap::updatePairListRemove:LP address not included");
		require(_removeRobustSwapPair != robustSwapBNBPair,"RobustSwap::updatePairListRemove:robustSwapBNBPair cannot be excluded");		
		emit UpdatePairListRemove(operator, _removeRobustSwapPair);		
		_robustSwapPairLPList[_removeRobustSwapPair] = false;
	}

	/**
	* @dev Update the autoTrigger settings
	* For autoliquidity and autoSell
	* Can only be called by the current operator
	*/
	function updateAutoTrigger(bool _autoTrigger, uint256 _autoTriggerAmount, uint16 _autoTriggerAmountRate) external onlyOperator {
		require(_autoTriggerAmount > 0,"RobustSwap::updateAutoTrigger:Amount cannot be 0");
		require(_autoTriggerAmountRate > 0,"RobustSwap::updateAutoTrigger:Trigger amount rate cannot be 0");
		require(_autoTriggerAmountRate <= 10000, "RobustSwap::updateAutoTrigger:Trigger amount rate must not exceed the maximum rate");
		emit UpdateAutoTrigger(operator, autoTrigger, _autoTrigger, autoTriggerAmount, _autoTriggerAmount, autoTriggerAmountRate, _autoTriggerAmountRate);
		if(_autoTrigger != autoTrigger)
			autoTrigger = _autoTrigger;
		if(_autoTriggerAmount != autoTriggerAmount)
			autoTriggerAmount = _autoTriggerAmount;
		if(_autoTriggerAmountRate != autoTriggerAmountRate)
			autoTriggerAmountRate = _autoTriggerAmountRate;
	}

	/**
	* @dev Update the bot guard blocks setting
	* Can only be called by the current operator
	* Setting the blocks guard to 0 disabled this feature
	*/
	function updateBotGuard(uint8 _botGuardBlocks) external onlyOperator {
		require(_botGuardBlocks <= MAXIMUM_BOTGUARD_BLOCKS, "RobustSwap::updateBotGuard:botGuardBlocks cannot exceed maximum blocks");
		emit UpdateBotGuard(operator, botGuardBlocks, _botGuardBlocks);
		if(_botGuardBlocks != botGuardBlocks)
			botGuardBlocks = _botGuardBlocks;
	}

	/**
	* @dev Update autoSell status
	* Can only be called by the current operator
	*/
	function updateAutoSellEnabled(bool _autoSellEnabled) external onlyOperator {
		if (!_autoSellEnabled)
			require(autoSellEnabled,"RobustSwap::updateAutoSellEnabled:autoSell is disabled");		
		if (_autoSellEnabled)
			require(!autoSellEnabled,"RobustSwap::updateAutoSellEnabled:autoSell is enabled");
		emit UpdateAutoSellEnabled(operator, _autoSellEnabled);		
		autoSellEnabled = _autoSellEnabled;
	}

	/**
	* @dev Update autoLiquidity status
	* Can only be called by the current operator
	*/
	function updateAutoLiquidityStatus(bool _autoLiquidityEnabled) external onlyOperator {
		if (!_autoLiquidityEnabled)
			require(autoLiquidityEnabled,"RobustSwap::updateAutoLiquidityStatus:autoLiquidityEnabled is disabled");
		if (_autoLiquidityEnabled)
			require(!autoLiquidityEnabled,"RobustSwap::updateAutoLiquidityStatus:autoLiquidityEnabled is enabled");
		emit UpdateAutoLiquidityStatus(operator, _autoLiquidityEnabled);		
		autoLiquidityEnabled = _autoLiquidityEnabled;
	}

	/**
	* @dev Update the RobustSwap router
	* Can only be called by the current operator
	*/
	function updateRobustSwapRouter(address _routerAddress) external onlyOperator {
		require(_routerAddress != address(0),"RobustSwap::updateRobustSwapRouter:Router address cannot be zero address");
		require(_routerAddress != routerAddress(),"RobustSwap::updateRobustSwapRouter:No change, current router address");
		_robustSwapRouter = IUniswapV2Router02(_routerAddress);
		robustSwapBNBPair = IUniswapV2Factory(_robustSwapRouter.factory()).getPair(address(this), _robustSwapRouter.WETH());
		require(robustSwapBNBPair != address(0), "RobustSwap::updateRobustSwapRouter:Invalid pair address.");
		emit UpdateRobustSwapRouter(operator, address(_robustSwapRouter), robustSwapBNBPair);
		_robustSwapPairLPList[robustSwapBNBPair] = true;
	}

	/**
	* @dev Burn any or all RBS from the contract balance
	* Setting amount to 0 will burn the RBS available balance
	* Can only be called by the current operator
	*/
	function balanceBurnRBS(uint256 _amount) external onlyOperator timelockedOperator {
		IBEP20 token = IBEP20(address(this));
		uint256 balanceRBS = balanceOf(address(this));		
		require(balanceRBS > 0,"RobustSwap::balanceBurnRBS:Nothing to burn");
		require(_amount <= balanceRBS,"RobustSwap::balanceBurnRBS:Insufficient balance to burn");		
		balanceRBS = _amount > 0 ? _amount : balanceRBS;
		emit BalanceBurnRBS(operator, balanceRBS);		
		token.transfer(BURN_ADDRESS, balanceRBS);
	}

	/**
	* @dev Withdraw any token balance from the RBS contract
	* Setting amount to 0 will withdraw the token available balance
	* Can only be called by the current operator
	*/
	function balanceWithdrawToken(IBEP20 _tokenAddress, address _recipient, uint256 _amount) external onlyOperator timelockedOperator {		
		require(address(_tokenAddress) != address(0),"RobustSwap::balanceWithdrawToken:Token address cannot be zero address");		
		require(address(_tokenAddress) != address(this),"RobustSwap::balanceWithdrawToken:Token address cannot be this address");		
		require(_recipient != address(0),"RobustSwap::balanceWithdrawToken:Recipient cannot be zero address");
		uint256 balanceToken = _tokenAddress.balanceOf(address(this));
		require(balanceToken > 0,"RobustSwap::balanceWithdrawToken:Token has no balance to withdraw");
		require(_amount <= balanceToken,"RobustSwap::balanceWithdrawToken:Insufficient token balance to withdraw");
		balanceToken = _amount > 0 ? _amount : balanceToken;		
		emit BalanceWithdrawToken(operator, address(_tokenAddress), balanceToken);
		_tokenAddress.transfer(_recipient, balanceToken);
	}

}