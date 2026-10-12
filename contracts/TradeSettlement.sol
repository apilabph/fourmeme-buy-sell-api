// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
import "./SettlementBase.sol";

abstract contract PancakeSettlement is SettlementBase {
    address public constant WRAPPED =
        address(bytes20(hex"bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"));
    address public constant V2_FACTORY =
        address(bytes20(hex"ca143ce32fe78f1f7019d7d551a6402fc5350c73"));
    address public constant V2_ROUTER =
        address(bytes20(hex"10ed43c718714eb63d5aa57b78b54704e256024e"));
    address public constant V3_FACTORY =
        address(bytes20(hex"0bfbcf9fa4f9c56b0f40a671ad40e0805a091865"));
    address public constant V3_ROUTER =
        address(bytes20(hex"13f4ea83d0bd40e75c8222255bc855a974568dd4"));
    function _pair(address token, address pool) internal view returns (bool) {
        if (pool == address(0)) return false;
        return
            IV2Pair(pool).factory() == V2_FACTORY &&
            IV2Factory(V2_FACTORY).getPair(token, WRAPPED) == pool &&
            ((IV2Pair(pool).token0() == token &&
                IV2Pair(pool).token1() == WRAPPED) ||
                (IV2Pair(pool).token1() == token &&
                    IV2Pair(pool).token0() == WRAPPED));
    }
    function _v3(
        address token,
        address pool
    ) internal view returns (uint24 tier) {
        tier = IV3Pool(pool).fee();
        if (
            IV3Pool(pool).factory() != V3_FACTORY ||
            IV3Factory(V3_FACTORY).getPool(token, WRAPPED, tier) != pool
        ) revert UnsupportedMarket();
    }
    function _dexBuy(
        address token,
        uint8 venue,
        uint24 tier,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) internal {
        if (venue == 1) {
            address[] memory p = new address[](2);
            p[0] = WRAPPED;
            p[1] = token;
            IV2Router(V2_ROUTER)
                .swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: amount
            }(0, p, recipient, deadline);
        } else if (venue == 2) {
            uint256 beforeWrapped = IERC20(WRAPPED).balanceOf(address(this));
            IWrapped(WRAPPED).deposit{value: amount}();
            _approve(WRAPPED, V3_ROUTER, amount);
            IV3Router(V3_ROUTER).exactInputSingle(
                IV3Router.ExactInputSingleParams(
                    WRAPPED,
                    token,
                    tier,
                    recipient,
                    amount,
                    0,
                    0
                )
            );
            _approve(WRAPPED, V3_ROUTER, 0);
            uint256 unspent = IERC20(WRAPPED).balanceOf(address(this)) -
                beforeWrapped;
            if (unspent > 0) IWrapped(WRAPPED).withdraw(unspent);
        } else revert UnsupportedMarket();
    }
    function _dexSell(
        address token,
        uint8 venue,
        uint24 tier,
        uint256 amount,
        uint256 deadline
    ) internal {
        if (venue == 1) {
            address[] memory p = new address[](2);
            p[0] = token;
            p[1] = WRAPPED;
            _approve(token, V2_ROUTER, amount);
            IV2Router(V2_ROUTER)
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    amount,
                    0,
                    p,
                    address(this),
                    deadline
                );
            _approve(token, V2_ROUTER, 0);
        } else if (venue == 2) {
            uint256 beforeBalance = IERC20(WRAPPED).balanceOf(address(this));
            _approve(token, V3_ROUTER, amount);
            IV3Router(V3_ROUTER).exactInputSingle(
                IV3Router.ExactInputSingleParams(
                    token,
                    WRAPPED,
                    tier,
                    address(this),
                    amount,
                    0,
                    0
                )
            );
            _approve(token, V3_ROUTER, 0);
            IWrapped(WRAPPED).withdraw(
                IERC20(WRAPPED).balanceOf(address(this)) - beforeBalance
            );
        } else revert UnsupportedMarket();
    }
}

interface IFourHelper {
    function getTokenInfo(
        address
    )
        external
        view
        returns (
            uint256,
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        );
    function tryBuy(
        address,
        uint256,
        uint256
    )
        external
        view
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );
}
interface IFour {
    function buyTokenAMAP(address, address, uint256, uint256) external payable;
    function sellToken(address, uint256) external;
}
contract TradeSettlement is PancakeSettlement {
    address public constant HELPER =
        address(bytes20(hex"f251f83e40a78868fcfa3fa4599dad6494e46034"));
    address public constant MANAGER =
        address(bytes20(hex"5c952063c7fc8610ffdb798152d69f0b9550762b"));
    function stage(
        address token
    ) public view override returns (uint8, address, uint24) {
        (
            uint256 version,
            address manager,
            address quote,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool graduated
        ) = IFourHelper(HELPER).getTokenInfo(token);
        if (version != 2 || manager != MANAGER || quote != address(0))
            revert UnsupportedMarket();
        if (!graduated) return (0, MANAGER, 0);
        address pair = IV2Factory(V2_FACTORY).getPair(token, WRAPPED);
        if (!_pair(token, pair)) revert UnsupportedMarket();
        return (1, pair, 0);
    }
    function _buy(
        address token,
        uint8 venue,
        address,
        uint24 tier,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) internal override {
        if (venue == 0) {
            // Helper values include current protocol/tax/launch fees. Keep all of them inside the user's budget.
            uint256 funds = amount;
            for (uint256 i = 0; i < 4; i++) {
                (
                    address manager,
                    address quote,
                    ,
                    ,
                    ,
                    uint256 value,
                    ,
                    uint256 recommendedFunds
                ) = IFourHelper(HELPER).tryBuy(token, 0, funds);
                if (
                    manager != MANAGER ||
                    quote != address(0) ||
                    value == 0 ||
                    recommendedFunds == 0
                ) revert UnsupportedMarket();
                if (value <= amount) {
                    IFour(MANAGER).buyTokenAMAP{value: value}(
                        token,
                        recipient,
                        recommendedFunds,
                        0
                    );
                    return;
                }
                uint256 excess = value - amount;
                if (excess >= funds) revert InvalidRequest();
                funds -= excess;
            }
            revert InvalidRequest();
        } else _dexBuy(token, venue, tier, amount, recipient, deadline);
    }
    function _sell(
        address token,
        uint8 venue,
        address,
        uint24 tier,
        uint256 amount,
        uint256 deadline
    ) internal override {
        if (venue == 0) {
            _approve(token, MANAGER, amount);
            IFour(MANAGER).sellToken(token, amount);
            _approve(token, MANAGER, 0);
        } else _dexSell(token, venue, tier, amount, deadline);
    }
}
