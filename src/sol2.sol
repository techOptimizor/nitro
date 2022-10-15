//SPDX-License-Identifier;
pragma solidity 0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IpriceB.sol";
import "./Interfaces/ILPToken.sol";
import "./DataToken.sol";

//import "./Interfaces/Isol2.sol";
contract exm {
    IERC20 public USDC;
    DataToken public NFT;
    IpriceB public priceB;

    uint public priceEth;
    uint public priceUsdc;
    uint public LiquidationFee = 10;
    uint public fees = 3;
    uint256 private _nextId = 1;
    uint256 private _nextPoolId = 1;
    uint256 public liquidatedCollateralAmount;
    uint64 internal LasttimeStamp;
    uint32 internal SecondsInYear = 31536000;

    struct POSITIONS {
        uint256 _liquidity;
        uint256 _interestRate;
        uint256 _collateralFactor;
        uint256 _poolId;
        uint256 _k;
    }

    struct BORROWTRANSACTIONS {
        uint256 _interestRateBorrowedAt;
        uint256 _collateralFactorBorrowedAt;
        uint256 _totalBorrowed;
        address _borrower;
    }

    struct LIQUIDATEDTRANSACTIONS {
        uint256 _poolId;
        uint _amountLiquidatedFromPool;
    }

    struct NFTSTOPOOL {
        uint _tokenId;
    }

    POSITIONS[] public positions;
    mapping(uint => POSITIONS) public pos;
    mapping(uint => mapping(uint => uint)) public getPoolId;
    BORROWTRANSACTIONS[] public borrowtransactions;
    NFTSTOPOOL[] public nftsToPool;
    LIQUIDATEDTRANSACTIONS[] public liquidatedTransactions;
    mapping(uint => uint) public NftIdToAmount;
    // mapping (uint => mapping (uint => bool)) public pos;
    mapping(address => BORROWTRANSACTIONS) public bos;
    mapping(uint => NFTSTOPOOL[]) public poolToNftId;
    mapping(uint => uint) public NftIdToPoolId;
    mapping(uint => mapping(uint => bool)) public collateralFactorToIntrestRate;
    mapping(uint => mapping(uint => uint)) public amountBorrowedAtAnArea;
    mapping(address => uint256) public CollateralAmount;
    mapping(address => uint256) public CollateralValue;
    mapping(address => uint256) public borrowedValue;
    mapping(address => uint256) public totalMCR;
    mapping(address => uint256) public totalICR;
    mapping(uint256 => mapping(uint256 => uint256))
        public collateralFactor_IntrestRateTopoolIds;
    mapping(address => BORROWTRANSACTIONS[]) public addressToBorrowTransaction;

    error NOLIQUIDITYATTHEPOINT();
    error CANT_BE_LIQUIDATED();
    error NOT_OWING_THE();
    error POSITION_DOES_NOT_EXIST();
    error INVALID_AMOUNT();
    error INVALID_POOLID();
    error TimestampTooLarge();
    error INVALID_ADDRESS();

    event liquidityAdded(
        uint amount,
        address from,
        uint256 collateralFactor,
        uint256 interestRate
    );
    event created(
        uint256 indexed liquidity,
        uint256 indexed collateralFactor,
        uint256 indexed interestRate
    );
    event Borrowed(uint amount, address to, uint newLiquidity);
    event isLiquidationAllowed(
        address borrower,
        uint amountOwed,
        uint CollateralValue
    );
    event liquidated(
        address borrower,
        address liquidator,
        uint amountOwed,
        uint CollateralValue
    );
    event addressLiquidatable(address borrower);

    constructor(
        address _usdc,
        address _nft,
        address _price
    ) {
        LasttimeStamp = uint64(block.timestamp);
        USDC = IERC20(_usdc);
        NFT = DataToken(_nft);
        priceB = IpriceB(_price);
    }

    function getNowInternal() internal view virtual returns (uint64) {
        if (block.timestamp >= 2**64) revert TimestampTooLarge();
        return uint64(block.timestamp);
    }

    function accuredInterest() internal {
        uint64 now_ = getNowInternal();
        uint64 formerTime = LasttimeStamp;
        uint64 timeElapsed = now_ - formerTime;

        BORROWTRANSACTIONS memory data = bos[msg.sender];

        if (timeElapsed > 0) {
            if (
                totalMCR[msg.sender] != data._collateralFactorBorrowedAt &&
                totalICR[msg.sender] != data._interestRateBorrowedAt
            ) {
                uint totalborrowsofDiff = data._totalBorrowed;
                uint newTotalborrowsofDiff = (((totalICR[msg.sender] * 1e23) /
                    (SecondsInYear * 100)) *
                    timeElapsed *
                    totalborrowsofDiff);
                //bos[msg.sender]._totalBorrowed = newTotalborrowsofDiff;
                borrowedValue[msg.sender] += newTotalborrowsofDiff;
            } else {
                uint totalborrows = data._totalBorrowed;
                uint newTotalborrows = (((data._interestRateBorrowedAt * 1e23) /
                    (SecondsInYear * 100)) *
                    timeElapsed *
                    totalborrows);
                //bos[msg.sender]._totalBorrowed = newTotalborrows;
                borrowedValue[msg.sender] += newTotalborrows;
            }
        }

        LasttimeStamp = now_;
    }

    function addLiquidity(
        uint256 _amount,
        uint256 _collateralFactor,
        uint256 _interestRate
    ) external {
        priceUsdc = priceB.priceUsdc();
        if (
            collateralFactorToIntrestRate[_collateralFactor][_interestRate] ==
            false
        ) {
            _create(_amount, _collateralFactor, _interestRate);
            collateralFactorToIntrestRate[_collateralFactor][
                _interestRate
            ] = true;
        } else {
            uint poolIdToUpdate = getPoolId[_collateralFactor][_interestRate];
            _getPairAndUpdate(
                _amount,
                _collateralFactor,
                _interestRate,
                poolIdToUpdate
            );
        }
    }

    function _create(
        uint256 _amount,
        uint256 _collateralFactor,
        uint256 _interestRate
    ) internal returns (uint) {
        if (_amount <= 0) revert INVALID_AMOUNT();
        pos[_nextPoolId] = (
            POSITIONS({
                _liquidity: _amount,
                _interestRate: _interestRate,
                _collateralFactor: _collateralFactor,
                _poolId: _nextPoolId,
                _k: 1
            })
        );
        getPoolId[_collateralFactor][_interestRate] = _nextPoolId;
        //I DID SAME THING WITH collateralFactor_IntrestRateTopoolIds , TAKE NOTE AND CHANGE
        //positions.push(POSITIONS({_liquidity:_amount, _interestRate:_interestRate, _collateralFactor:_collateralFactor, _poolId:_nextPoolId, _k:1 }));
        collateralFactor_IntrestRateTopoolIds[_collateralFactor][
            _interestRate
        ] = _nextPoolId;
        NFTSTOPOOL[] storage data = poolToNftId[_nextPoolId];
        data.push(NFTSTOPOOL({_tokenId: _nextId}));
        uint toTransfer = (_amount * 1e8) / (priceUsdc);
        USDC.transferFrom(msg.sender, address(this), toTransfer);
        NFT.safeMint(
            msg.sender,
            _nextId,
            _amount,
            _collateralFactor,
            _interestRate,
            _nextPoolId
        );
        NftIdToAmount[_nextId] = _amount;
        NftIdToPoolId[_nextId] = _nextPoolId;
        _nextId++;
        _nextPoolId++;

        emit created(_amount, _collateralFactor, _interestRate);
        return (toTransfer);
    }

    function _getPairAndUpdate(
        uint256 _amount,
        uint256 _collateralFactor,
        uint256 _interestRate,
        uint256 _poolId
    ) internal {
        uint borrowed = amountBorrowedAtAnArea[_collateralFactor][
            _interestRate
        ];
        POSITIONS memory data = pos[_poolId];
        if (
            data._collateralFactor == _collateralFactor &&
            data._interestRate == _interestRate
        ) {
            if (borrowed == 0) {
                uint toTransfer = (_amount * 1e20) / (priceUsdc);
                USDC.transferFrom(msg.sender, address(this), toTransfer);
                NFT.safeMint(
                    msg.sender,
                    _nextId,
                    _amount,
                    _collateralFactor,
                    _interestRate,
                    data._poolId
                );
                NftIdToAmount[_nextId] = _amount;
                NftIdToPoolId[_nextId] = data._poolId;
                _nextId++;
                // data._liquidity+=_amount;
                pos[_poolId]._liquidity += _amount;
            } else {
                uint utilizationRate = (borrowed * 100) / data._liquidity;
                uint percentageIntrestGrowth = (utilizationRate *
                    _interestRate) / 100;
                //uint k=(data._k*percentageIntrestGrowth)/100;
                uint toTransfer = (_amount * 1e8) / (priceUsdc);
                //data._k+=k;
                //uint liquidityprovided=_amount/k;
                //uint remainant=_amount-liquidityprovided;
                USDC.transferFrom(msg.sender, address(this), toTransfer);
                NFT.safeMint(
                    msg.sender,
                    _nextId,
                    _amount,
                    _collateralFactor,
                    _interestRate,
                    data._poolId
                );
                //NftIdToAmount[_nextId]=liquidityprovided;
                NftIdToPoolId[_nextId] = data._poolId;
                _nextId++;
                pos[_poolId]._liquidity += _amount;
                /*NFTSTOPOOL []storage nfts=poolToNftId[data._poolId];
                uint toDistribute=remainant/nfts.length;
                for (uint j;j<nfts.length;j++){
                    uint lp=poolToNftId[data._poolId][j]._tokenId;
                    NftIdToAmount[lp]+=toDistribute;

                }*/
            }
        }
        emit liquidityAdded(
            _amount,
            msg.sender,
            _collateralFactor,
            _interestRate
        );
    }

    function addCollateral() public payable {
        updatePrice();
        (bool sucess, ) = payable(address(this)).call{value: msg.value}("");
        require(sucess, "Transaction Failed");
        //address(this).balance + msg.value;
        CollateralAmount[msg.sender] += msg.value;
    }

    function withdrawCollateral(uint _amount) external payable {
        updatePrice();
        accuredInterest();
        if (_amount <= 0) revert INVALID_AMOUNT();
        if (borrowedValue[msg.sender] == 0) {
            require(
                _amount <= CollateralAmount[msg.sender],
                "amount greater than available collateral"
            );
            // address(this).balance-_amount;
            //reentreancy
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            require(sent, "Failed to send Ether");
            CollateralAmount[msg.sender] -= _amount;
        } else {
            BORROWTRANSACTIONS memory data = bos[msg.sender];
            if (data._borrower == msg.sender) {
                uint factor = (data._totalBorrowed * LiquidationFee) / 100;
                uint check = CollateralValue[msg.sender] -
                    (data._totalBorrowed + factor);
                require(
                    _amount < CollateralValue[msg.sender],
                    "amount greater than available collateral"
                );
                require(
                    _amount <= check,
                    "cant withdraw collateral used to support borrow"
                );
                //address(this).balance-_amount;
                (bool sent, ) = payable(msg.sender).call{value: _amount}("");
                require(sent, "Failed to send Ether");
                CollateralAmount[msg.sender] -= _amount;
            }
        }
    }

    function updatePrice() public {
        priceEth = priceB.priceEth();
        priceUsdc = priceB.priceUsdc();
        CollateralValue[msg.sender] =
            (CollateralAmount[msg.sender] * priceEth) /
            1e20;
    }

    function initBorrow(
        uint256 _amount,
        uint256 _collateralFactor,
        uint256 _interestRate
    ) internal {
        //LOOPING CAN BE ADJUSTED.
        uint poolIdToBorrow = getPoolId[_collateralFactor][_interestRate];
        POSITIONS memory data = pos[poolIdToBorrow];
        if (
            data._collateralFactor == _collateralFactor &&
            data._interestRate == _interestRate
        ) {
            uint liquidationFee = (CollateralValue[msg.sender] *
                LiquidationFee) / 100;
            uint si = CollateralValue[msg.sender] - liquidationFee;
            uint mt = (si * data._collateralFactor) / 100;
            require(
                CollateralValue[msg.sender] > _amount,
                "amount more than collateral value"
            );
            require(_amount <= mt, "amount greater than MCR for ur collateral");
            //uint toTransfer = (_amount * 1e20) / (priceUsdc);
            amountBorrowedAtAnArea[_collateralFactor][_interestRate] = _amount;
            borrowedValue[msg.sender] = _amount;
            USDC.transfer(msg.sender, _amount);
            data._liquidity -= _amount;
            pos[poolIdToBorrow]._liquidity -= _amount;
            bos[msg.sender] = BORROWTRANSACTIONS({
                _interestRateBorrowedAt: _interestRate,
                _collateralFactorBorrowedAt: _collateralFactor,
                _totalBorrowed: _amount,
                _borrower: msg.sender
            });
            // checks with arrays
            // borrowtransactions.push(
            //     BORROWTRANSACTIONS({
            //         _interestRateBorrowedAt: _interestRate,
            //         _collateralFactorBorrowedAt: _collateralFactor,
            //         _totalBorrowed: _amount,
            //         _borrower: msg.sender
            //     })
            // );
            //ARRAY OF STORAGE.
            BORROWTRANSACTIONS[] storage trx = addressToBorrowTransaction[
                msg.sender
            ];
            trx.push(
                BORROWTRANSACTIONS({
                    _interestRateBorrowedAt: _interestRate,
                    _collateralFactorBorrowedAt: _collateralFactor,
                    _totalBorrowed: _amount,
                    _borrower: msg.sender
                })
            );
            emit Borrowed(_amount, msg.sender, data._liquidity);
        }
    }

    /* function subBorrows (uint256 _amount, uint256 _collateralFactor, uint256 _interestRate) internal{
        updatePrice();   
        for (uint i; i<positions.length;i++){
            POSITIONS storage data=positions[i]; 
            if (data._collateralFactor==_collateralFactor && data._interestRate==_interestRate){
               BORROWTRANSACTIONS storage borrowData=borrowtransactions[i];
               if(borrowData._borrower==msg.sender){

                uint liquidationFee=(CollateralValue[msg.sender]*LiquidationFee)/100;
                uint mt=((CollateralValue[msg.sender]-liquidationFee)*data._collateralFactor)/100;
                uint predictedTotalBorrow=borrowedValue[msg.sender]+_amount;
                amountBorrowedAtAnArea[_collateralFactor][_interestRate]+=_amount;
                require(CollateralValue[msg.sender]>_amount, "amount more than collateral value");
                require(_amount<=mt, "amount greater than MCR for ur collateral"); 
                uint toTransfer=(_amount*1e20)/(priceUsdc);
                USDC.transfer( msg.sender, toTransfer);
                data._liquidity-=_amount;
                borrowedValue[msg.sender]+=_amount; 
                totalMCR[msg.sender]=_collateralFactor;
                borrowData._totalBorrowed+=_amount;
                emit Borrowed(_amount, msg.sender,data._poolId);    
               }
               else{
                borrowtransactions.push(BORROWTRANSACTIONS({_interestRateBorrowedAt:_interestRate, _collateralFactorBorrowedAt:_collateralFactor, _totalBorrowed:_amount, _borrower:msg.sender}));
                uint liquidationFee=(CollateralValue[msg.sender]*LiquidationFee)/100;
                uint mt=((CollateralValue[msg.sender]-liquidationFee)*data._collateralFactor)/100;
                require(_amount<=mt, "amount greater than MCR for ur collateral"); 
                for (uint j;j<borrowtransactions.length;j++){
                    BORROWTRANSACTIONS storage borrowData=borrowtransactions[i];
                    if 
                }
                uint predictedTotalBorrow=borrowedValue[msg.sender]+_amount;
                uint x=(borrowedValue[msg.sender]*100)/predictedTotalBorrow;
                uint y=(_amount*100)/predictedTotalBorrow;
                uint tmcr=x+y;
                amountBorrowedAtAnArea[_collateralFactor][_interestRate]+=_amount;
                require(CollateralValue[msg.sender]>_amount, "amount more than collateral value");

                require(_collateralFactor<=tmcr, "amount greater than total mcr");
                uint toTransfer=(_amount*1e20)/(priceUsdc);
                USDC.transfer( msg.sender, toTransfer);
                data._liquidity-=_amount;
                borrowedValue[msg.sender]+=_amount;
                totalMCR[msg.sender]=tmcr;
                emit Borrowed(_amount, msg.sender,data._liquidity);

               }

            }
        }
    }*/

    function subBorrows(
        uint256 _amount,
        uint256 _collateralFactor,
        uint256 _interestRate
    ) internal {
        uint poolIdToBorrow = getPoolId[_collateralFactor][_interestRate];
        POSITIONS memory data = pos[poolIdToBorrow];
        uint liquidationFee = (LiquidationFee * CollateralValue[msg.sender]) /
            100;
        uint newColValue = CollateralValue[msg.sender] - liquidationFee;
        //uint toTransfer = (_amount * 1e20) / (priceUsdc);
        if (
            data._collateralFactor == _collateralFactor &&
            data._interestRate == _interestRate
        ) {
            BORROWTRANSACTIONS memory borrowData = bos[msg.sender];
            if (msg.sender == borrowData._borrower) {
                //function
                uint maxBorrow = (newColValue * data._collateralFactor) / 100;
                require(_amount <= maxBorrow);
                amountBorrowedAtAnArea[_collateralFactor][
                    _interestRate
                ] += _amount;
                USDC.transfer(msg.sender, _amount);
                //data._liquidity-=_amount;
                pos[poolIdToBorrow]._liquidity -= _amount;
                borrowedValue[msg.sender] += _amount;
                totalMCR[msg.sender] = _collateralFactor;
                totalICR[msg.sender] = _interestRate;
                bos[msg.sender]._totalBorrowed += _amount;
                emit Borrowed(_amount, msg.sender, data._poolId);
            } else {
                uint presumedTotaldebt = borrowedValue[msg.sender] + _amount;
                uint yColFactor = (_amount * 100) / presumedTotaldebt;
                uint bColFactor = (borrowedValue[msg.sender] * 100) /
                    presumedTotaldebt;
                uint newCollateralFactor = (bColFactor * totalMCR[msg.sender]) +
                    (yColFactor * _collateralFactor);
                totalMCR[msg.sender] = newCollateralFactor;
                uint MaxiBorrow = (newColValue * newCollateralFactor) / 100;
                require(_amount <= MaxiBorrow);
                //checks
                amountBorrowedAtAnArea[_collateralFactor][
                    _interestRate
                ] += _amount;
                USDC.transfer(msg.sender, _amount);
                borrowedValue[msg.sender] += _amount;
                pos[poolIdToBorrow]._liquidity -= _amount;
                bos[msg.sender]._totalBorrowed += _amount;
                uint newinterestrate = (bColFactor * totalICR[msg.sender]) +
                    (yColFactor * _interestRate);
                totalICR[msg.sender] = newinterestrate;
                emit Borrowed(_amount, msg.sender, data._poolId);

                // borrowtransactions.push(BORROWTRANSACTIONS({_interestRateBorrowedAt:_interestRate, _collateralFactorBorrowedAt:_collateralFactor, _totalBorrowed:_amount, _borrower:msg.sender  }));
            }
        } else {
            revert POSITION_DOES_NOT_EXIST();
        }
    }

    function borrow(
        uint _amount,
        uint256 _collateralFactor,
        uint256 _interestRate
    ) external {
        accuredInterest();
        updatePrice();
        if (borrowedValue[msg.sender] == 0) {
            initBorrow(_amount, _collateralFactor, _interestRate);
        } else {
            subBorrows(_amount, _collateralFactor, _interestRate);
        }
    }

    function repay(uint _amount) external {
        updatePrice();
        accuredInterest();
        BORROWTRANSACTIONS memory data = bos[msg.sender];
        //EFFECT OF ACCURED INTERESET
        uint amountOwed = data._totalBorrowed;
        if (data._borrower == msg.sender && amountOwed == _amount) {
            uint poolOwed = collateralFactor_IntrestRateTopoolIds[
                data._collateralFactorBorrowedAt
            ][data._interestRateBorrowedAt];
            delete bos[msg.sender];
            // borrowtransactions.pop();
            POSITIONS memory positiontrx = pos[poolOwed];
            if (positiontrx._poolId == poolOwed) {
                positiontrx._liquidity += _amount;
                pos[poolOwed]._liquidity = positiontrx._liquidity;
                //uint toTransfer = (_amount * 1e20) / (priceUsdc);
                USDC.transferFrom(msg.sender, address(this), _amount);
                borrowedValue[msg.sender] -= _amount;
            }
        } else if (data._borrower == msg.sender && amountOwed != _amount) {
            uint poolOwed = collateralFactor_IntrestRateTopoolIds[
                data._collateralFactorBorrowedAt
            ][data._interestRateBorrowedAt];
            POSITIONS memory positiontrx = pos[poolOwed];
            if (positiontrx._poolId == poolOwed) {
                positiontrx._liquidity += _amount;
                pos[poolOwed]._liquidity = positiontrx._liquidity;
                // uint toTransfer = (_amount * 1e20) / (priceUsdc);
                USDC.transferFrom(msg.sender, address(this), _amount);
                borrowedValue[msg.sender] -= _amount;
                bos[msg.sender]._totalBorrowed -= _amount;
            }
        } else {
            revert NOT_OWING_THE();
        }
    }

    // function repayMultiple(uint[] memory poolid) public {
    //     for (uint i; i < poolid.length; i++) {}
    // }

    //withdraw

    function withdrawLiquidity(uint256 _id, uint _amount) external {
        //MISTAKE OF NEXTID TO ID
        updatePrice();
        require(
            NftIdToAmount[_id] >= _amount,
            "you dont have the amount you are trying to withdraw"
        );
        require(_amount > 0);
        POSITIONS memory data = pos[NftIdToPoolId[_id]];
        if (NftIdToAmount[_id] == _amount) {
            NftIdToAmount[_id] = 0;
            NFT.transferFrom(msg.sender, address(this), _id);
            NFT.burn(_id);
            data._liquidity -= _amount;
            pos[NftIdToPoolId[_id]]._liquidity = data._liquidity;
            //uint toTransfer = (_amount * 1e20) / (priceUsdc);
            USDC.transfer(msg.sender, _amount);
        } else {
            //POSITIONS memory data = pos[NftIdToPoolId[_id]];
            if (data._poolId == NftIdToPoolId[_id]) {
                NftIdToAmount[_id] -= _amount;
                NFT.transferFrom(msg.sender, address(this), _id);
                NFT.burn(_id);
                data._liquidity -= _amount;
                pos[NftIdToPoolId[_id]]._liquidity = data._liquidity;
                //uint toTransfer = (_amount * 1e20) / (priceUsdc);
                USDC.transfer(msg.sender, _amount);
                NFT.safeMint(
                    msg.sender,
                    _nextId,
                    NftIdToAmount[_nextId],
                    data._collateralFactor,
                    data._interestRate,
                    data._poolId
                );
                NftIdToPoolId[_nextId] = data._poolId;
                _nextId++;
            }
        }
    }

    function chackIfLiquidationIsAllowed(address _borrower)
        external
        returns (bool CAN_BE_LIQUIDATED)
    {
        updatePrice();
        accuredInterest();
        BORROWTRANSACTIONS memory data = bos[_borrower];
        if (data._borrower == _borrower) {
            uint liquidationThreshold = data._collateralFactorBorrowedAt +
                LiquidationFee;
            uint healtFactor = ((CollateralValue[_borrower] *
                liquidationThreshold) / borrowedValue[_borrower]) * 100;
            uint amountOwed = data._totalBorrowed;
            emit isLiquidationAllowed(
                _borrower,
                amountOwed,
                CollateralValue[_borrower]
            );

            if (healtFactor <= 1) {
                return true;
            } else {
                return false;
            }
        }
    }

    function liquidate(address _borrower) external {
        updatePrice();
        accuredInterest();

        BORROWTRANSACTIONS memory data = bos[_borrower];
        if (data._borrower == _borrower) {
            uint liquidationThreshold = data._collateralFactorBorrowedAt +
                LiquidationFee;
            uint healtFactor = ((CollateralValue[_borrower] *
                liquidationThreshold) / borrowedValue[_borrower]) * 100;
            uint amountOwed = data._totalBorrowed;
            if (healtFactor <= 1) {
                uint poolId = collateralFactor_IntrestRateTopoolIds[
                    data._collateralFactorBorrowedAt
                ][data._interestRateBorrowedAt];
                liquidatedTransactions.push(
                    LIQUIDATEDTRANSACTIONS({
                        _poolId: poolId,
                        _amountLiquidatedFromPool: CollateralAmount[_borrower]
                    })
                );
                liquidatedCollateralAmount += CollateralAmount[_borrower];
                CollateralAmount[_borrower] = 0;
                amountOwed = 0;
                emit liquidated(
                    _borrower,
                    msg.sender,
                    amountOwed,
                    CollateralValue[_borrower]
                );
            } else {
                revert CANT_BE_LIQUIDATED();
            }
        }
    }

    function getUserBorrowData(address _borrower)
        external
        returns (BORROWTRANSACTIONS memory borrowersInfo)
    {
        accuredInterest();
        BORROWTRANSACTIONS memory data = bos[_borrower];
        if (data._borrower == _borrower) {
            return data;
        }
    }

    function isLiquidatable_(address account) external {
        accuredInterest();
        BORROWTRANSACTIONS memory data = bos[account];
        if (data._borrower == address(0)) revert INVALID_ADDRESS();
        uint liquidationThreshold = data._collateralFactorBorrowedAt +
            LiquidationFee;
        uint healtFactor = ((CollateralValue[data._borrower] *
            liquidationThreshold) / borrowedValue[data._borrower]) * 100;
        if (healtFactor <= 1) {
            data._borrower;
            emit addressLiquidatable(data._borrower);
        }
    }

    function buyLiquidatedCollaterals(
        uint _minAmount,
        uint _baseAmount,
        address _recipient
    ) external {
        /*uint discount=(3*_baseAmount)/100;
        uint amount=_baseAmount-discount;
        uint toTransfer=(amount*1e20)/(priceEth);
        require(amount>=_minAmount, "less than minAmount");
        address(this).balance-toTransfer;
        (bool sent, ) = payable(_recipient).call{value: toTransfer}("");
        require(sent, "Failed to send Ether");
        liquidatedCollateralAmount-=toTransfer;       uint256 _poolId;
        uint _amountLiquidatedFromPool;
        */
        for (uint i; i < liquidatedTransactions.length; i++) {
            LIQUIDATEDTRANSACTIONS memory data = liquidatedTransactions[i];
            uint discount = (3 * _baseAmount) / 100;
            uint amount = _baseAmount - discount;
            uint remainant = 0;
            //if (amount>)
        }
    }

    function totalLiquidaterdValue() external view returns (uint) {
        return liquidatedCollateralAmount;
    }

    receive() external payable {
        //addCollateral();
    }

    // fallback() external payable{}
}
