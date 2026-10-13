export const config = {
  slug: "fourmeme-buy-sell-api",
  short: "Four.Meme",
  name: "Four.Meme BNB Buy and Sell API",
  host: "fourmeme-trade",
  network: "BNB Smart Chain · 56",
  native: "BNB",
  evm: true,
  four: true,
  accent: "#6cff32",
  port: 8814,
  fee: "0x4629EE1f5d2A87D7b8Ed9982DA8ad6A5bd3F01F0",
  hero: "Buy and Sell Four.Meme API",
  lead: "Check a token’s current market, understand its amount units and prepare a transaction your own bot can verify and sign.",
  status:
    "Market inspection is available. Quote, trade and approval endpoints need the operator’s settlement contract deployment. Funded trading and fee collection are not active.",
  statusLabel: "Inspection beta",
  stage: "Four.Meme → V2",
  coverage: [
    "Manager V2 bonding curves with a native-BNB quote.",
    "Canonical Pancake V2 graduation pools.",
    "Exact approvals and total buy-budget checks in the implemented settlement adapter.",
  ],
  limits: [
    "Manager V1, non-BNB pairs and V3 pools.",
    "Unsupported or unknown market registrations.",
    "Sells taxed on transfer from your wallet into the settlement contract.",
  ],
  evidence:
    "Read-only state-overlay tests exercised a curve and Pancake V2 buy/sell roundtrip against mainnet protocol state. The router was not deployed and no funds moved.",
  special:
    "Bonding-curve sells must use raw token amounts divisible by 1,000,000,000. Do not round upward. The playground uses this conservative rule for every sell; the API checks the actual stage.",
  api: "https://fourmeme-trade.apilabph.workers.dev",
  github: "https://github.com/apilabph/fourmeme-buy-sell-api",
};
