pragma solidity >= 0.5.0 < 0.6.0;

contract SavingAccountParameters {
    string public ratesURL;
	string public tokenNames;
    address[] public tokenAddresses;

    constructor() public payable{
        //ratesURL = "json(http://dip.deipool.io/dipPool/coinPirce).[ZB,QC,USDT,ETH,DIP,BNB,HT,OKB,LEO].usd";
    	tokenNames = "ZB,QC,USDT,ETH,DIP,BNB,HT,OKB,LEO";
//update the url and the name
		tokenAddresses = new address[](9);
		tokenAddresses[0] = 0xBd0793332e9fB844A52a205A233EF27a5b34B927; // zb
		tokenAddresses[1] = 0xE74B35425fE7E33EA190b149805baF31139a8290; //qc
		tokenAddresses[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;//usdt
		tokenAddresses[3] = 0x000000000000000000000000000000000000000E; //eth
		tokenAddresses[4] = 0xd1517663883e2Acc154178Fb194E80e8bBc29730; //dip
		tokenAddresses[5] = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52; //bnb
		tokenAddresses[6] = 0x0316EB71485b0Ab14103307bf65a021042c6d380;  //ht
		tokenAddresses[7] = 0x75231F58b43240C9718Dd58B4967c5114342a86c; // okb
		tokenAddresses[8] = 0x2AF5D2aD76741191D15Dfe7bF6aC92d4Bd912Ca3; //leo

		
	}

	function getTokenAddresses() public view returns(address[] memory){
        return tokenAddresses;
    }
}
