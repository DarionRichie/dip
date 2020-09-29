pragma solidity >= 0.5.0 < 0.6.0;

import "./TokenInfoLib.sol";
import "./SymbolsLib.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./Ownable.sol";
import "./provableAPI.sol";
import "./SavingAccountParameters.sol";
import "./IERC20.sol";
import "./ABDK.sol";
import "https://raw.githubusercontent.com/smartcontractkit/chainlink/develop/evm-contracts/src/v0.5/ChainlinkClient.sol";
import "./tokenbasic.sol";

contract SavingAccount is Ownable,ChainlinkClient {
	using TokenInfoLib for TokenInfoLib.TokenInfo;
	using SymbolsLib for SymbolsLib.Symbols;
	//using SafeMath for uint256;
	using SignedSafeMath for int256;
	//uint constant CUSTOM_GAS_LIMIT = 6000000;
	
	event borrowed(address onwer,uint256 amount,address tokenaddress);
	event depositTokened(address onwer,uint256 amount,address tokenaddress);
	event repayed(address onwer,uint256 amount,address tokenaddress);
	event withdrawed(address onwer,uint256 amount,address tokenaddress);
	event liquidated(address onwer);
	
	
	//奖励开始时间
	uint256 startTime = now - 1 days;
	//奖励的天数
    int128 dayNums = 0;
    //奖励基数
    int128 baseReward = 80000;
    //今日借贷池可获得奖励 每日变动 根据公式计算得来
    int256  todayTotalReward = 0;
    // int256 public divdepositsnumber = 1;
    // int256 public divloansnumber = 1;


    uint256 public totalDepositsAmount = 1 ;
        //今日资金池总共借币金额 USD
    uint256 public totalBorrowAmount = 1 ;

    int256 public todayloans = 0;
    int256 public todaydeposits = 0;
    
    int256 loansuseedreward = 0;
    int256 depositsuseedreward = 0;
	
	mapping(address=>bool) public isReward;
	
	//bytes32 public ethereumPrice;
    //string public wangxin;
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    uint256 public who = 1;
    
    //string public aa;
	struct Account {
		// Note, it's best practice to use functions minusAmount, addAmount, totalAmount 
		// to operate tokenInfos instead of changing it directly. 
		mapping(address => TokenInfoLib.TokenInfo) tokenInfos;
		bool active;
	}
	int256 public totalReward;
	mapping(address => Account) accounts;
	mapping(address => int256) totalDeposits;
	mapping(address => int256) totalLoans;
	mapping(address => int256) totalCollateral;
    
	address[] activeAccounts;

	SymbolsLib.Symbols symbols;

	event LogNewProvableQuery(string description);
	event LogNewPriceTicker(string price);
	int256 constant BASE = 10**6;
	uint256 SUPPLY_APR_PER_SECOND = 3170;	// SUPPLY APR = 10%. 3170 / 10^12 * 60 * 60 * 24 * 365 = 0.05 
	uint256 BORROW_APR_PER_SECOND = 4755;	// BORROW APR = 15%. 4755 / 10^12 * 60 * 60 * 24 * 365 = 0.07
	
	int BORROW_LTV = 66; //TODO check is this 60%?
	int LIQUIDATE_THREADHOLD = 85;

	constructor() public {
	    setPublicChainlinkToken();
        oracle = 0x2f90A6D021db21e1B2A077c5a37B3C7E75D15b7e;
        jobId = "50fc4215f89443d185b061e5d7af9490";
        fee = 0.1 * 10 ** 18; // 0.1 LINK
		SavingAccountParameters params = new SavingAccountParameters();
		address[] memory tokenAddresses = params.getTokenAddresses();
		//TODO This needs improvement as it could go out of gas
		symbols.initialize(params.ratesURL(), params.tokenNames(), tokenAddresses);
		
	}

	//TODO
// 	function initialize(string memory ratesURL, string memory tokenNames, address[] memory tokenAddresses) public onlyOwner {
// 		symbols.initialize(ratesURL, tokenNames, tokenAddresses);
// 	}

	/** 
	 * Gets the total amount of balance that give accountAddr stored in saving pool. 
	 */
	 
	function() external payable {}
	function getAccountTotalUsdValue(address accountAddr) public view returns (int256 usdValue) {
		return getAccountTotalUsdValue(accountAddr, true).add(getAccountTotalUsdValue(accountAddr, false));
	}
    
    function setPrice(string memory result) public onlyOwner{
        symbols.parseRatesbyself(result);
    }
    
	function getAccountTotalUsdValue(address accountAddr, bool isPositive) private view returns (int256 usdValue){
		int256 totalUsdValue = 0;
		for(uint i = 0; i < getCoinLength(); i++) {
			if (isPositive && accounts[accountAddr].tokenInfos[symbols.addressFromIndex(i)].totalAmount(block.timestamp) >= 0) {
				totalUsdValue = totalUsdValue.add(
					accounts[accountAddr].tokenInfos[symbols.addressFromIndex(i)].totalAmount(block.timestamp)
					.mul(int256(symbols.priceFromIndex(i)))
					.div(BASE)
				);
			}
			if (!isPositive && accounts[accountAddr].tokenInfos[symbols.addressFromIndex(i)].totalAmount(block.timestamp) < 0) {
				totalUsdValue = totalUsdValue.add(
					accounts[accountAddr].tokenInfos[symbols.addressFromIndex(i)].totalAmount(block.timestamp)
					.mul(int256(symbols.priceFromIndex(i)))
					.div(BASE)
				);
			}
		}
		return totalUsdValue;
	}
	
	
	
    function bytes32ToString(bytes32 x) private returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
    
    
    /**
     * Create a Chainlink request to retrieve API response, find the target price
     * data, then multiply by 100 (to remove decimal places from price).
     */
    function requestPrice() public returns (bytes32 requestId) 
    {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        request.add("get", "http://159.138.27.178:3000/api/getmarket");
        if(who==1){
            request.add("path", "total1");
        }else if(who==2){
            request.add("path", "total2");
        }else request.add("path", "total3");
        return sendChainlinkRequestTo(oracle, request, fee);
    }
    
    
    //写成two string 
    /**
     * 
     * Receive the response in the form of uint256
     */ 
    function fulfill(bytes32 _requestId, bytes32 _price) public recordChainlinkFulfillment(_requestId)
    {
        //ethereumPrice = _price;
        string memory wangxin = bytes32ToString(_price);
        //jie xie shiyong duiying 
        symbols.parseRates(wangxin,who);
        if(who!=3){
            who = who+1;
        }else who = 1;
    }
    
	

	/** 
	 * Get the overall state of the saving pool
	 */
	function getMarketState() public view returns (address[] memory addresses,
		int256[] memory deposits,
		int256[] memory loans,
		int256[] memory collateral)
	{
		uint coinsLen = getCoinLength();

		addresses = new address[](coinsLen);
		deposits = new int256[](coinsLen);
		loans = new int256[](coinsLen);
		collateral = new int256[](coinsLen);

		for (uint i = 0; i < coinsLen; i++) {
			address tokenAddress = symbols.addressFromIndex(i);
			addresses[i] = tokenAddress;
			deposits[i] = totalDeposits[tokenAddress];
			loans[i] = totalLoans[tokenAddress];
			collateral[i] = totalCollateral[tokenAddress];
		}

		return (addresses, deposits, loans, collateral);
	}

	/*
	 * Get the state of the given token
	 */
	function getTokenState(address tokenAddress) public view returns (int256 deposits, int256 loans, int256 collateral)
	{
		return (totalDeposits[tokenAddress], totalLoans[tokenAddress], totalCollateral[tokenAddress]);
	}

	/** 
	 * Get all balances for the sender's account
	 */
	
	function getBalances() public view returns (address[] memory addresses, int256[] memory balances)
	{
		uint coinsLen = getCoinLength();

		addresses = new address[](coinsLen);
		balances = new int256[](coinsLen);

		for (uint i = 0; i < coinsLen; i++) {
			address tokenAddress = symbols.addressFromIndex(i);
			addresses[i] = tokenAddress;
			balances[i] = tokenBalanceOf(tokenAddress);
		}

		return (addresses, balances);
	}

	function getActiveAccounts() public view returns (address[] memory) {
		return activeAccounts;
	}

	function getLiquidatableAccounts() public view returns (address[] memory) {
		address[] memory liquidatableAccounts;
		uint returnIdx;
		//TODO `activeAccounts` not getting removed from array.
		//TODO its always increasing. Call to this function needing
		//TODO more gas, however, it will not be charged in ETH.
		//TODO What could be the impact? 
		for (uint i = 0; i < activeAccounts.length; i++) {
			address targetAddress = activeAccounts[i];
			if (
				int256(getAccountTotalUsdValue(targetAddress, false).mul(-1)).mul(100)
				>
				getAccountTotalUsdValue(targetAddress, true).mul(LIQUIDATE_THREADHOLD)
			) {
				liquidatableAccounts[returnIdx++] = (targetAddress);
			}
		}
		return liquidatableAccounts;
	}

	function getCoinLength() public view returns (uint256 length){
		return symbols.getCoinLength();
	}

	function tokenBalanceOf(address tokenAddress) public view returns (int256 amount) {
		return accounts[msg.sender].tokenInfos[tokenAddress].totalAmount(block.timestamp);
	}

	function getCoinAddress(uint256 coinIndex) public view returns (address) {
		return symbols.addressFromIndex(coinIndex);
	}

	function getCoinToUsdRate(uint256 coinIndex) public view returns(uint256) {
		return symbols.priceFromIndex(coinIndex);
	}

	function borrow(address tokenAddress, uint256 amount) public payable {
	    require(tokenAddress!=0xd1517663883e2Acc154178Fb194E80e8bBc29730,"can't borrow dip");
		require(accounts[msg.sender].active, "Account not active, please deposit first.");
		TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[tokenAddress];
		require(tokenInfo.totalAmount(block.timestamp) < int256(amount), "Borrow amount less than available balance, please use withdraw instead.");
		require(
			(
				int256(getAccountTotalUsdValue(msg.sender, false) * -1)
				.add(int256(amount.mul(symbols.priceFromAddress(tokenAddress))))
				.div(BASE)
			).mul(100)
			<=
			(getAccountTotalUsdValue(msg.sender, true)).mul(BORROW_LTV),
			 "Insufficient collateral.");
        //reward 
          if(isReward[msg.sender])
            getreward();
        
        
        emit borrowed(msg.sender,amount,tokenAddress);
		tokenInfo.minusAmount(amount, BORROW_APR_PER_SECOND, block.timestamp);
		totalLoans[tokenAddress] = totalLoans[tokenAddress].add(int256(amount));
		totalCollateral[tokenAddress] = totalCollateral[tokenAddress].sub(int256(amount));
        send(msg.sender, amount, tokenAddress);
        // if(loansuseedreward<int256(todayTotalReward)){
        //     //reward by number of USD
        //     int256 reward = int256(amount).mul(int256(symbols.priceFromAddress(tokenAddress))).mul(divloansnumber).div(10**6);
        //     if(reward<=(todayTotalReward-loansuseedreward)){
        //         //repay the dip
        //         loansuseedreward+=reward;
        //         repaybydipreward(uint256(reward));
        //     }else{
        //         repaybydipreward(uint256(todayTotalReward-loansuseedreward));
        //         loansuseedreward = todayTotalReward;
        //     }
            
        // }
        // todayloans+=int256(amount).mul(int256(symbols.priceFromAddress(tokenAddress)));
        
	}

	function repay(address tokenAddress, uint256 amount) public payable {
		require(accounts[msg.sender].active, "Account not active, please deposit first.");
		TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[tokenAddress];

		int256 amountOwedWithInterest = tokenInfo.totalAmount(block.timestamp);
		require(amountOwedWithInterest <= 0, "Balance of the token must be negative. To deposit balance, please use deposit button.");

		int256 amountBorrowed = tokenInfo.getCurrentTotalAmount().mul(-1); // get the actual amount that was borrowed (abs)
		int256 amountToRepay = int256(amount);
		tokenInfo.addAmount(amount, 0, block.timestamp);
        
        
        int256 other = tokenInfo.totalnumber().mul(-1);
        
		// check if paying interest
		if (amountToRepay > amountBorrowed) {
			// add interest (if any) to total deposit
			totalDeposits[tokenAddress] = totalDeposits[tokenAddress].add(amountToRepay.sub(amountBorrowed));
			// loan are reduced by amount payed
			totalLoans[tokenAddress] = totalLoans[tokenAddress].sub(amountBorrowed);
			
		}
		else {
			// loan are reduced by amount payed
			totalLoans[tokenAddress] = totalLoans[tokenAddress].sub(amountToRepay);
		}

		// collateral increased by amount payed 
		totalCollateral[tokenAddress] = totalCollateral[tokenAddress].add(amountToRepay);
		emit repayed(msg.sender,amount,tokenAddress);
        
		
		
        receive(msg.sender, uint256((int256(amountBorrowed)-other).mul(int256(50)).div(100)).add(uint256(amount)-uint256(int256(amountBorrowed)-other)), tokenAddress);
        receivemyself(msg.sender,uint256(int256(amountBorrowed)-other).mul(50).div(100),tokenAddress);
	}


// 	function repaybydipreward(uint256 amount) private {
// 	        address dipToken = 0xd1517663883e2Acc154178Fb194E80e8bBc29730;
// 		    TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[dipToken];
// 		    int256 currentBalance = tokenInfo.getCurrentTotalAmount();

// 		    uint256 LastRatio;
//             if(totalDeposits[dipToken]!=0){
//             LastRatio = SUPPLY_APR_PER_SECOND.mul(uint256(totalLoans[dipToken])).div(uint256(totalDeposits[dipToken]));
//             }
            
// 		// deposited amount is new balance after addAmount minus previous balance
//     		int256 depositedAmount = tokenInfo.addAmount(uint256(amount), LastRatio, block.timestamp) - currentBalance;
//     		//depositedAmount = tokenInfo.addAmount(uint256(amount), SUPPLY_APR_PER_SECOND, block.timestamp) - currentBalance;
//     		totalDeposits[dipToken] = totalDeposits[dipToken].add(depositedAmount);
//     		totalCollateral[dipToken] = totalCollateral[dipToken].add(depositedAmount);
// 	}

	/** 
	 * Deposit the amount of tokenAddress to the saving pool. 
	 */
	function depositToken(address tokenAddress, uint256 amount) public payable {
		TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[tokenAddress];
		if (!accounts[msg.sender].active) {
			accounts[msg.sender].active = true;
			isReward[msg.sender]=false;
			activeAccounts.push(msg.sender);
		}
        if(isReward[msg.sender])
            getreward();
		int256 currentBalance = tokenInfo.getCurrentTotalAmount();

		require(currentBalance >= 0,
			"Balance of the token must be zero or positive. To pay negative balance, please use repay button.");
        //change the ratio 
        uint256 LastRatio;
        if(totalDeposits[tokenAddress]!=0){
        LastRatio = SUPPLY_APR_PER_SECOND.mul(uint256(totalLoans[tokenAddress])).div(uint256(totalDeposits[tokenAddress]));
        }
		// deposited amount is new balance after addAmount minus previous balance
		int256 depositedAmount = tokenInfo.addAmount(amount, LastRatio, block.timestamp) - currentBalance;
		totalDeposits[tokenAddress] = totalDeposits[tokenAddress].add(depositedAmount);
		totalCollateral[tokenAddress] = totalCollateral[tokenAddress].add(depositedAmount);
        emit depositTokened(msg.sender,amount,tokenAddress);

        //TODO do reward 
        
        // if(depositsuseedreward<int256(todayTotalReward)){
        //     //reward by number of USD
        //     int256 reward = depositedAmount.mul(int256(symbols.priceFromAddress(tokenAddress))).mul(divdepositsnumber).div(10**6);
        //     if(reward<=(todayTotalReward-depositsuseedreward)){
        //         //repay the dip
        //         depositsuseedreward+=reward;
        //         repaybydipreward(uint256(reward));
        //     }else{
        //         repaybydipreward(uint256(todayTotalReward-depositsuseedreward));
        //         depositsuseedreward = todayTotalReward;
        //     }
            
        // }
        // todaydeposits+=depositedAmount.mul(int256(symbols.priceFromAddress(tokenAddress)));
		receive(msg.sender, amount, tokenAddress);
	}

	/**
	 * Withdraw tokens from saving pool. If the interest is not empty, the interest
	 * will be deducted first.
	 */
	function withdrawToken(address tokenAddress, uint256 amount) public payable {
		require(accounts[msg.sender].active, "Account not active, please deposit first.");
		TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[tokenAddress];

		require(tokenInfo.totalAmount(block.timestamp) >= int256(amount), "Insufficient balance.");
  		require(int256(getAccountTotalUsdValue(msg.sender, false).mul(-1)).mul(100) <= (getAccountTotalUsdValue(msg.sender, true) - int256(amount.mul(symbols.priceFromAddress(tokenAddress)))).mul(BORROW_LTV).div(BASE);
        emit withdrawed(msg.sender,amount,tokenAddress);
		tokenInfo.minusAmount(amount, 0, block.timestamp);
		totalDeposits[tokenAddress] = totalDeposits[tokenAddress].sub(int256(amount));
		totalCollateral[tokenAddress] = totalCollateral[tokenAddress].sub(int256(amount));

		send(msg.sender, amount, tokenAddress);		
	}

	function liquidate(address targetAddress) public payable {
		require(
			int256(getAccountTotalUsdValue(targetAddress, false).mul(-1))
			.mul(100)
			>
			getAccountTotalUsdValue(targetAddress, true).mul(LIQUIDATE_THREADHOLD),
			"The ratio of borrowed money and collateral must be larger than 85% in order to be liquidated.");
        emit liquidated(targetAddress);
		uint coinsLen = getCoinLength();
		for (uint i = 0; i < coinsLen; i++) {
			address tokenAddress = symbols.addressFromIndex(i);
			TokenInfoLib.TokenInfo storage tokenInfo = accounts[targetAddress].tokenInfos[tokenAddress];
			int256 totalAmount = tokenInfo.totalAmount(block.timestamp);
			if (totalAmount > 0) {
				send(msg.sender, uint256(totalAmount), tokenAddress);
			} else if (totalAmount < 0) {
				//TODO uint256(-totalAmount) this will underflow - Critical Security Issue
				//TODO what is the reason for doing this???
				receive(msg.sender, uint256(-totalAmount), tokenAddress);
			}
		}
	}

	function receive(address from, uint256 amount, address tokenAddress) private {
		if (symbols.isEth(tokenAddress)) {
            require(msg.value == amount, "The amount is not sent from address.");
		} else {
			//When only tokens received, msg.value must be 0
			require(msg.value == 0, "msg.value must be 0 when receiving tokens");
			//require(IERC20(tokenAddress).transferFrom(from, address(this), amount), "Token transfer failed");
			if(tokenAddress!=0xdAC17F958D2ee523a2206206994597C13D831ec7){
			    IERC20(tokenAddress).transferFrom(from, address(this), amount);
			}else{
			    basic(tokenAddress).transferFrom(from,address(this),amount);
			}
			
		}
	}
	
	
	function receivemyself(address from, uint256 amount, address tokenAddress) private {
		if (symbols.isEth(tokenAddress)) {
            require(msg.value == amount, "The amount is not sent from address.");
            //TODO   
            
		} else {
			//When only tokens received, msg.value must be 0
			require(msg.value == 0, "msg.value must be 0 when receiving tokens");
			//require(IERC20(tokenAddress).transferFrom(from, address(this), amount), "Token transfer failed");
			if(tokenAddress!=0xdAC17F958D2ee523a2206206994597C13D831ec7){
			IERC20(tokenAddress).transferFrom(from, 0x06D847d33f4E7DAcB7115aC896358dc93e7c9A5a, amount);
			}else{
			 basic(tokenAddress).transferFrom(from,0x06D847d33f4E7DAcB7115aC896358dc93e7c9A5a,amount);
			}
		}
	}

	function send(address to, uint256 amount, address tokenAddress) private {
		if (symbols.isEth(tokenAddress)) {
			//TODO need to check for re-entrancy security attack
			//TODO Can this ETH be received by a contract?
			msg.sender.transfer(amount);
		} else {
			//require(IERC20(tokenAddress).transfer(to, amount), "Token transfer failed");
			if(tokenAddress!=0xdAC17F958D2ee523a2206206994597C13D831ec7){
			IERC20(tokenAddress).transfer(to, amount);
			}else{
			    basic(tokenAddress).transfer(to, amount);
			}
		}
	}

	/** 
	 * Callback function which is used to parse query the oracle. Once 
	 * parsed results from oracle, it will recursively call oracle for data. 
	 **/
// 	function __callback(bytes32,  string memory result) public {
// 		require(msg.sender == provable_cbAddress(), "Unauthorized address");
// 		emit LogNewPriceTicker(result);
// 		aa = result;
		
// 		// updatePrice(30 * 60); // Call from external
        
// 	}


 
   
	

    //getInfo()  获取基本信息，TODO 测试便于查看 正式部署去掉
    function getInfo() public view returns(uint256, int128, int256) {
        return (startTime, dayNums, todayTotalReward);
    }
	
	//更新今日借贷总奖励 各50%  需要管理员每天调用触发  测试调成10秒
	function updateTodayTotalRewards() public onlyOwner {
	   require(now - startTime >=  1 days, "At least 1 day");
	   dayNums = dayNums + 1;
	   startTime = startTime + 1 days;

	   //TODO 指数计算 小数不能这么计算 是错误的 待改正
	   ///更新对应的算法 ----- 只写了这么样计算出来;
		int128 precision = 10000000;
		int128 BASE_Rate = precision-precision*dayNums/60; //转化为整数存储 如果需要更多的精度使用10**n其中n越大越准确
		uint256 count = 0;
		int128[] memory list = new int128[](15);//可以删除记录十个精度每一个的位数的值 1,0两者
		int128 Yun_number = BASE_Rate;//迭代的初始值
		int128 d = 0;//计算本来是整数变成小数64.64
		if(dayNums<=180){
		for(int128 i=0;i<15;i++){ //这里的精度是10可以进行修改——————让精度更大
			Yun_number = Yun_number*2;
			int128 A = 1;
			
			if(Yun_number>precision){ //100000和上面的精度对应
				d = d+(A<<(63-count));
				Yun_number-=precision;
				list[count] = int128(1);
				count+=1;
			}else{
				//d = d+(B<<(63-count));
				list[count] = int128(0);
				count+=1;
			}
			
		}

		//得到的最后值为 万为单位的币:
		todayTotalReward = int256(ABDKMath64x64.toInt(ABDKMath64x64.exp(d)*baseReward));//为int64;转换为uint256 --- 没有负数

		}else if(dayNums<=25*365){
		    todayTotalReward = int256(10000);
		    
		    
		}
		 
	   //---AllRwd是最后的结果
	   //todayTotalReward = baseReward ** (1 - dayNums / 180);
	   totalReward+=todayTotalReward*10**18;
	   todayTotalReward = todayTotalReward*10**18/2;
	   
	   
	    uint length = getCoinLength();
	    uint accountLengt = activeAccounts.length;
	    for(uint i=0;i<accountLengt;i++){
	        isReward[activeAccounts[i]] = true;
	    }
	    
        totalBorrowAmount=1;
        totalDepositsAmount=1;
        //获取总计借贷金额
		for (uint i = 0; i < length; i++) {
			address tokenAddress = symbols.addressFromIndex(i);
			totalDepositsAmount = totalDepositsAmount.add(uint256(totalDeposits[tokenAddress]).mul(uint256(symbols.priceFromIndex(i))));
			totalBorrowAmount = totalBorrowAmount.add(uint256(totalLoans[tokenAddress]).mul(uint256(symbols.priceFromIndex(i))));
		}
		totalBorrowAmount = totalBorrowAmount>1?totalBorrowAmount-1:totalBorrowAmount;
		totalDepositsAmount = totalDepositsAmount>1?totalDepositsAmount-1:totalDepositsAmount;
	   
	}

	
	
	function getreward() private {

        
        isReward[msg.sender] = false;
        
        uint length = getCoinLength();
        
        int256 everyoneDepositAmount;
        int256 everyoneBorrowAmount;
        //获取总计借贷金额
		//get myself reward
		address dipToken = 0xd1517663883e2Acc154178Fb194E80e8bBc29730;
		TokenInfoLib.TokenInfo storage tokenInfo = accounts[msg.sender].tokenInfos[dipToken];
		int256 currentBalance = tokenInfo.getCurrentTotalAmount();
		
    for(uint k = 0; k < length; k++) {
        address tokenAddr = symbols.addressFromIndex(k);

        //int256 amount = accounts[activeAccounts[k]].tokenInfos[tokenAddr].totalAmount(block.timestamp);
        //int256 amountUSD = int256(amount).mul(int256(uint256(symbols.priceFromIndex(k))));
        
        int256 amount = accounts[msg.sender].tokenInfos[tokenAddr].totalAmount(block.timestamp);
        int256 amountUSD = int256(amount).mul(int256(uint256(symbols.priceFromIndex(k))));  //TODO 测试 乘以汇率直接写死
        //int256 amountUSD = int256(amount).mul(int256(uint256(1)));
        if(amountUSD > 0) {
            everyoneDepositAmount = int256(everyoneDepositAmount).add(int256(amountUSD));
        } 
        if (amountUSD < 0) {
            everyoneBorrowAmount = int256(everyoneBorrowAmount).add(int256(int256(amountUSD).mul(-1)));
        }
        
    }
    uint256 todayBorrowReward = uint256(everyoneBorrowAmount).mul(uint256(todayTotalReward)).div(uint256(totalBorrowAmount));
	uint256 todayDepositReward = uint256(everyoneDepositAmount).mul(uint256(todayTotalReward)).div(uint256(totalDepositsAmount));
	
    
    int256 depositedAmount = tokenInfo.addAmount(uint256(todayBorrowReward), SUPPLY_APR_PER_SECOND, block.timestamp) - currentBalance;
	depositedAmount = tokenInfo.addAmount(uint256(todayDepositReward), SUPPLY_APR_PER_SECOND, block.timestamp) - currentBalance;
	totalDeposits[dipToken] = totalDeposits[dipToken].add(depositedAmount);
	totalCollateral[dipToken] = totalCollateral[dipToken].add(depositedAmount);
	
	}
    
}
    
		    
// 		    //收益计算与发放
		    
// 		    uint256 todayBorrowReward = uint256(everyoneBorrowAmount).mul(uint256(todayTotalReward)).div(uint256(totalBorrowAmount));
// 		    uint256 todayDepositReward = uint256(everyoneDepositAmount).mul(uint256(todayTotalReward)).div(uint256(totalDepositsAmount));
		    
		    
// 		    //用户当前余额 发放奖励为Dip Token
// 		    address dipToken = 0x79F850CeaA8150197c4CE82F8e2FC87B72e5D63C;
// 		    TokenInfoLib.TokenInfo storage tokenInfo = accounts[activeAccounts[j]].tokenInfos[dipToken];
// 		    int256 currentBalance = tokenInfo.getCurrentTotalAmount();

		    

		// deposited amount is new balance after addAmount minus previous balance
    		
		    
		    
		  //  int256 currentBalance = accounts[activeAccounts[j]].tokenInfos[dipToken].balance;
		  //  currentBalance =  currentBalance.add(int256(todayBorrowReward)).add(int256(todayDepositReward));
		  
		  //  //奖励发放 即增加用户Dip Token余额
		  //  accounts[activeAccounts[j]].tokenInfos[dipToken].balance = currentBalance;
    //         totalDeposits[dipToken] = totalDeposits[dipToken].add(int256(todayBorrowReward)).add(int256(todayDepositReward));
    //         totalCollateral[dipToken] =totalCollateral[dipToken].add(int256(todayBorrowReward)).add(int256(todayDepositReward));
		    //重置为零 计算下一个用户奖励
		    //xiao shu wei   
		
		
		
		
	
	
	//奖励发放  需要管理员每天调用触发
// 	function rewardDistribution() public onlyOwner returns(int256) {
// 	    //require(now - startTime >= 1 days, "At least one day");
// 	    require(now - startTime >=  1 days, "At least one day");
// 	    startTime = startTime + 1 days;
//         //今日资金池总共存币金额 USD
//         int256 totalDepositsAmount = 1 ;
//         //今日资金池总共借币金额 USD
//         int256 totalBorrowAmount = 1 ;
        
//         uint length = getCoinLength();
        
//         //获取总计借贷金额
// 		for (uint i = 0; i < length; i++) {
// 			address tokenAddress = symbols.addressFromIndex(i);
// 			totalDepositsAmount = totalDepositsAmount.add(int256(totalDeposits[tokenAddress]).mul(int256(symbols.priceFromIndex(i))));
// 			totalBorrowAmount = totalBorrowAmount.add(int256(totalLoans[tokenAddress]).mul(int256(symbols.priceFromIndex(i))));
// 		}
// 		totalBorrowAmount = totalBorrowAmount>1?totalBorrowAmount-1:totalBorrowAmount;
// 		totalDepositsAmount = totalDepositsAmount>1?totalDepositsAmount-1:totalDepositsAmount;
// // 		for (uint i = 0; i < length; i++) {
// // 			totalDepositsAmount = 100000;   //TODO 测试直接写死  因为暂时无法获取币种对应美元价格
// // 			totalBorrowAmount = 50000;      //TODO 测试直接写死  因为暂时无法获取币种对应美元价格
// // 		}
        
//         //所有活跃用户
//         uint userLength =  activeAccounts.length;
		
	    
// 	     //用户收益计算与发放
// 		 for (uint j = 0; j < userLength; j++) {
		     
// 		     //每个用户此时借币金额
// 		     int256 everyoneBorrowAmount = 0;
// 		     //每个用户此时存币金额
// 		     int256 everyoneDepositAmount = 0;
		     
//             for(uint k = 0; k < length; k++) {
//                 address tokenAddr = symbols.addressFromIndex(k);
       
//                 //int256 amount = accounts[activeAccounts[k]].tokenInfos[tokenAddr].totalAmount(block.timestamp);
//                 //int256 amountUSD = int256(amount).mul(int256(uint256(symbols.priceFromIndex(k))));
                
//                 int256 amount = accounts[activeAccounts[j]].tokenInfos[tokenAddr].totalAmount(block.timestamp);
//                 int256 amountUSD = int256(amount).mul(int256(uint256(symbols.priceFromIndex(k))));  //TODO 测试 乘以汇率直接写死
//                 //int256 amountUSD = int256(amount).mul(int256(uint256(1)));
//                 if(amountUSD > 0) {
//                     everyoneDepositAmount = int256(everyoneDepositAmount).add(int256(amountUSD));
//                 } 
//                 if (amountUSD < 0) {
//                     everyoneBorrowAmount = int256(everyoneBorrowAmount).add(int256(int256(amountUSD).mul(-1)));
//                 }
// 		    }
		    
// 		    //收益计算与发放
		    
// 		    uint256 todayBorrowReward = uint256(everyoneBorrowAmount).mul(uint256(todayTotalReward)).div(uint256(totalBorrowAmount));
// 		    uint256 todayDepositReward = uint256(everyoneDepositAmount).mul(uint256(todayTotalReward)).div(uint256(totalDepositsAmount));
		    
		    
// 		    //用户当前余额 发放奖励为Dip Token
// 		    address dipToken = 0x79F850CeaA8150197c4CE82F8e2FC87B72e5D63C;
// 		    TokenInfoLib.TokenInfo storage tokenInfo = accounts[activeAccounts[j]].tokenInfos[dipToken];
// 		    int256 currentBalance = tokenInfo.getCurrentTotalAmount();

		    

// 		// deposited amount is new balance after addAmount minus previous balance
//     		int256 depositedAmount = tokenInfo.addAmount(uint256(todayBorrowReward), SUPPLY_APR_PER_SECOND, block.timestamp) - currentBalance;
//     		depositedAmount = tokenInfo.addAmount(uint256(todayDepositReward), SUPPLY_APR_PER_SECOND, block.timestamp) - currentBalance;
//     		totalDeposits[dipToken] = totalDeposits[dipToken].add(depositedAmount);
//     		totalCollateral[dipToken] = totalCollateral[dipToken].add(depositedAmount);
		    
		    
// 		  //  int256 currentBalance = accounts[activeAccounts[j]].tokenInfos[dipToken].balance;
// 		  //  currentBalance =  currentBalance.add(int256(todayBorrowReward)).add(int256(todayDepositReward));
		  
// 		  //  //奖励发放 即增加用户Dip Token余额
// 		  //  accounts[activeAccounts[j]].tokenInfos[dipToken].balance = currentBalance;
//     //         totalDeposits[dipToken] = totalDeposits[dipToken].add(int256(todayBorrowReward)).add(int256(todayDepositReward));
//     //         totalCollateral[dipToken] =totalCollateral[dipToken].add(int256(todayBorrowReward)).add(int256(todayDepositReward));
// 		    //重置为零 计算下一个用户奖励
// 		    everyoneBorrowAmount = 0;
// 		    everyoneDepositAmount = 0;//xiao shu wei   
// 		}
// 		 return totalDepositsAmount;
// 	}
	
