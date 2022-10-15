// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/sol2.sol";
import "../src/DataToken.sol";
import "../src/LPtoken.sol";
import "../src/priceB.sol";

contract exmText is Test {
    event created(
        uint256 indexed liquidity,
        uint256 indexed collateralFactor,
        uint256 indexed interestRate
    );
    error INVALID_AMOUNT();
    error NOT_OWING_THE();

    exm public lend;
    DataToken public nft;
    MyToken public usdc;
    priceb public price;
    address payable owner;
    address payable spender = payable(makeAddr("tony"));

    function setUp() public {
        owner = payable(msg.sender);
        vm.startPrank(owner);
        nft = new DataToken();
        usdc = new MyToken();
        price = new priceb();
        lend = new exm(address(usdc), address(nft), address(price));
        usdc.mint(owner, 100000000000000000000000000000);
        usdc.approve(address(lend), type(uint256).max);

        price.setpriceUsdc(1000000);
        price.setpriceEth(1000000000);
    }

    function testAddColl() public {
        uint balanceBefore = address(lend).balance;
        lend.addCollateral{value: 1 ether}();
        uint balanceAfter = address(lend).balance;

        assertEq(balanceBefore + 1 ether, balanceAfter);
    }

    function testWithdrawColl() public {
        lend.addCollateral{value: 1 ether}();
        uint256 preBalance = address(this).balance;
        lend.withdrawCollateral(1 ether);
        uint256 postBalance = address(this).balance;
        uint gas = ((preBalance + 1 ether) - postBalance);
        assertEq(preBalance + 1 ether, postBalance + gas);
        // assertApproxEqAbs(preBalance + 1 ether, postBalance, 30000000);
    }

    function testWithdrawWIthoutCol() public {
        vm.expectRevert("amount greater than available collateral");
        lend.withdrawCollateral(0.5 ether);
        vm.expectRevert(INVALID_AMOUNT.selector);
        lend.withdrawCollateral(0);
    }

    function testAddLiquidity() public {
        vm.expectEmit(true, true, true, false);
        emit created(1000, 70, 10);
        lend.addLiquidity(1000, 70, 10);
        uint poolid = lend.collateralFactor_IntrestRateTopoolIds(70, 10);
        (uint _liquidity, , , uint _poolId, ) = (lend.pos(1));
        assertTrue(lend.collateralFactorToIntrestRate(70, 10));
        assertEq(_liquidity, 1000);
        assertEq(poolid, _poolId);

        testUpdateLiquidity();
    }

    function testUpdateLiquidity() internal {
        (uint _liquidityBefore, , , uint _poolIdBefore, ) = (lend.pos(1));
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidity, , , uint _poolId, ) = (lend.pos(1));
        assertEq(_liquidity, _liquidityBefore + 3000);
        assertEq(_poolId, _poolIdBefore);
    }

    function testWithdrawLiquidity() public {
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidity, , , , ) = (lend.pos(1));
        nft.approve(address(lend), 1);
        lend.withdrawLiquidity(1, 3000);
        (uint _liquidityAfter, , , , ) = (lend.pos(1));
        assertEq(_liquidity - 3000, _liquidityAfter);
    }

    function testWithdrawLiquidityHalf() public {
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidity, , , , ) = (lend.pos(1));
        nft.approve(address(lend), 1);
        lend.withdrawLiquidity(1, 2900);
        (uint _liquidityAfter, , , , ) = (lend.pos(1));
        assertEq(_liquidity - 2900, _liquidityAfter);
    }

    function testWithdrawLiquidityMoreThan() public {
        lend.addLiquidity(3000, 70, 10);
        nft.approve(address(lend), 1);
        vm.expectRevert("you dont have the amount you are trying to withdraw");
        lend.withdrawLiquidity(1, 30001);
    }

    function testBorrow() public {
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidityBefore, , , , ) = (lend.pos(1));
        vm.stopPrank();
        startHoax(spender);
        lend.addCollateral{value: 1 ether}();
        lend.borrow(1000, 70, 10);
        (, , uint borrowed, address borrower) = lend.bos(spender);
        (uint _liquidity, , , , ) = (lend.pos(1));
        assertEq(borrowed, 1000);
        assertEq(_liquidityBefore - 1000, _liquidity);
        assertEq(borrower, spender);
        assertEq(lend.borrowedValue(spender), 1000);

        testBorrowAgain();
    }

    function testBorrowAgain() internal {
        (uint _liquidityBefore, , , , ) = (lend.pos(1));
        lend.borrow(500, 70, 10);
        (, , uint borrowed, address borrower) = lend.bos(spender);
        (uint _liquidity, , , , ) = (lend.pos(1));
        assertEq(borrowed, 1500);
        assertEq(_liquidityBefore - 500, _liquidity);
        assertEq(borrower, spender);
        assertEq(lend.borrowedValue(spender), 1500);
    }

    function testRepay() public {
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidityBefore, , , , ) = (lend.pos(1));
        vm.stopPrank();
        startHoax(spender);
        lend.addCollateral{value: 1 ether}();
        usdc.mint(spender, 1000);
        lend.borrow(1000, 70, 10);
        usdc.approve(address(lend), type(uint256).max);
        lend.repay(1000);
        (, , uint borrowed, ) = lend.bos(spender);
        (uint _liquidity, , , , ) = (lend.pos(1));
        assertEq(borrowed, 0);
        assertEq(_liquidityBefore, _liquidity);
        assertEq(lend.borrowedValue(spender), 0);
    }

    function testRepayHalf() public {
        lend.addLiquidity(3000, 70, 10);
        (uint _liquidityBefore, , , , ) = (lend.pos(1));
        vm.stopPrank();
        startHoax(spender);
        lend.addCollateral{value: 1 ether}();
        usdc.mint(spender, 1000);
        lend.borrow(1000, 70, 10);
        usdc.approve(address(lend), type(uint256).max);
        lend.repay(500);
        (, , uint borrowed, ) = lend.bos(spender);
        (uint _liquidity, , , , ) = (lend.pos(1));
        assertEq(borrowed, 500);
        assertEq(_liquidityBefore - 500, _liquidity);
        assertEq(lend.borrowedValue(spender), 500);
    }

    function testRepayRevert() public {
        lend.addLiquidity(3000, 70, 10);
        vm.stopPrank();
        startHoax(spender);
        lend.addCollateral{value: 1 ether}();
        usdc.mint(spender, 1000);
        usdc.approve(address(lend), type(uint256).max);
        vm.expectRevert(NOT_OWING_THE.selector);
        lend.repay(1000);
    }

    fallback() external payable {}
}
