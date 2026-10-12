import { parseAbi } from "viem";
import config from "./config.json" with { type: "json" };
import { read, snapshot, same } from "./trading.js";
import { requireThat } from "./evm-rpc.js";
const wrapped = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c",
  zero = "0x0000000000000000000000000000000000000000";
const factory = "0xca143ce32fe78f1f7019d7d551a6402fc5350c73",
  v3factory = "0x0bfbcf9fa4f9c56b0f40a671ad40e0805a091865";
const dex = parseAbi([
  "function getPair(address,address) view returns(address)",
  "function getPool(address,address,uint24) view returns(address)",
  "function factory() view returns(address)",
  "function token0() view returns(address)",
  "function token1() view returns(address)",
  "function fee() view returns(uint24)",
]);
const flap = parseAbi([
  "function getTokenV8Safe(address) view returns((uint8 status,uint256 reserve,uint256 circulatingSupply,uint256 price,uint8 tokenVersion,uint256 r,uint256 h,uint256 k,uint256 dexSupplyThresh,address quoteTokenAddress,bool nativeToQuoteSwapEnabled,bytes32 extensionID,uint256 buyTaxRate,uint256 sellTaxRate,address pool,uint256 progress,uint8 lpFeeProfile,uint8 dexId))",
]);
const four = parseAbi([
  "function getTokenInfo(address) view returns(uint256 version,address manager,address quote,uint256 lastPrice,uint256 tradingFeeRate,uint256 minTradingFee,uint256 launchTime,uint256 offers,uint256 maxOffers,uint256 funds,uint256 maxFunds,bool liquidityAdded)",
]);
export async function inspect(rpc, token) {
  const b = await snapshot(rpc),
    at = b.number;
  let stage, market, details;
  const get = (to, name, args = [], abi = dex) =>
    read(rpc, to, name, args, at, abi);
  if (config.slug === "flap-bnb-buy-sell-api") {
    const portal = "0xe2ce6ab80874fa9fa2aae65d277dd6b8e65c9de0",
      s = await get(portal, "getTokenV8Safe", [token], flap);
    requireThat(
      s.tokenVersion <= 5 &&
        (same(s.quoteTokenAddress, zero) || same(s.quoteTokenAddress, wrapped)),
      "UNSUPPORTED_MARKET",
      "Only reviewed native-BNB token versions are supported.",
      422,
    );
    requireThat(
      [1, 4].includes(s.status),
      "MARKET_CLOSED",
      "Token is invalid, staged, dueling or killed.",
      422,
    );
    details = {
      tokenVersion: s.tokenVersion,
      protocolStatus: s.status,
      buyTaxRate: s.buyTaxRate.toString(),
      sellTaxRate: s.sellTaxRate.toString(),
      taxNote:
        "Raw protocol rates; actual net output is determined by transaction simulation.",
    };
    if (s.status === 1) {
      stage = 0;
      market = portal;
    } else {
      requireThat(
        s.dexId === 0,
        "UNSUPPORTED_MARKET",
        "Only canonical Pancake V2/V3 graduation pools are supported.",
        422,
      );
      const pair = await get(factory, "getPair", [token, wrapped]);
      market = s.pool;
      if (same(market, pair) && !same(pair, zero)) stage = 1;
      else {
        const fee = await get(market, "fee"),
          canonical = await get(v3factory, "getPool", [token, wrapped, fee]);
        requireThat(
          same(canonical, market),
          "POOL_MISMATCH",
          "Graduation pool is not canonical.",
          422,
        );
        stage = 2;
      }
    }
  } else {
    const s = await get(
      "0xf251f83e40a78868fcfa3fa4599dad6494e46034",
      "getTokenInfo",
      [token],
      four,
    );
    requireThat(
      s[0] === 2n &&
        same(s[1], "0x5c952063c7fc8610ffdb798152d69f0b9550762b") &&
        same(s[2], zero),
      "UNSUPPORTED_MARKET",
      "Only Four.Meme V2 native-BNB markets are supported.",
      422,
    );
    stage = s[11] ? 1 : 0;
    market =
      stage === 0 ? s[1] : await get(factory, "getPair", [token, wrapped]);
    requireThat(
      !same(market, zero),
      "MIGRATION_PENDING",
      "Canonical Pancake V2 pool is not available.",
      422,
    );
    details = {
      managerVersion: 2,
      liquidityAdded: s[11],
      protocolTradingFeeRate: s[4].toString(),
      minimumProtocolFeeWei: s[5].toString(),
      feeNote:
        "Dynamic taxes and launch fees may apply; the final quote uses the actual settlement call.",
    };
  }
  if (stage !== 0) {
    const [f, a, z] = await Promise.all([
      get(market, "factory"),
      get(market, "token0"),
      get(market, "token1"),
    ]);
    requireThat(
      same(f, stage === 1 ? factory : v3factory) &&
        ((same(a, token) && same(z, wrapped)) ||
          (same(a, wrapped) && same(z, token))),
      "POOL_MISMATCH",
      "Pool factory or pair identity differs.",
      422,
    );
  }
  const end = await rpc("eth_getBlockByNumber", [at, false]);
  requireThat(
    end?.number === at && end?.hash === b.hash,
    "SNAPSHOT_CHANGED",
    "Snapshot changed; retry.",
    409,
  );
  return {
    chainId: config.chainId,
    token,
    stage: config.stages[stage],
    stageId: stage,
    market,
    snapshot: { number: BigInt(at).toString(), hash: b.hash },
    ...details,
    tradingEnabled: false,
    warning:
      "Market observation only. Trading needs a deployed, verified settlement router and successful simulation.",
  };
}
