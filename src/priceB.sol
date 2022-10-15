import "./Interfaces/IOracle.sol";
contract priceb{

    IOracle public OracleEth=IOracle(0xa867815E2a4674C988463108F2e63097518ac3f7);
    IOracle public OracleUSDC=IOracle(0x0bbfd328F757120C5ad39b1Be122781A44701bc1);
    bytes oracleDataETH="0x5498BB86BC934c8D34FDA08E81D444153d0D06aD";
    bytes oracleDataUSDC="0xf988e4374165a081cd4647a5A9f46F158B10cF3D";
    uint public priceEth;
    uint public priceUsdc;

    function setPriceEth()public {
        uint EthPriceFeed=OracleEth.get(oracleDataETH);
        uint ethUsd=EthPriceFeed;
        //uint priceEthMantissa=(EthPriceFeed *ethUsd)/1e18;
        priceEth=ethUsd/1e16;      
    }



    function setPriceUsdc()public{
        uint usdcPriceFeed=OracleUSDC.get(oracleDataUSDC);
        uint priceUsdcMantissa=usdcPriceFeed;
        priceUsdc=priceUsdcMantissa/1e16;
    }

    function setPrice()public{
        setPriceUsdc();
        setPriceEth();
    }

        function setpriceUsdc(uint _priceUsdc) external{
        priceUsdc=_priceUsdc;
    }

        function setpriceEth(uint _priceETH) external{
        priceEth=_priceETH;
    }
}