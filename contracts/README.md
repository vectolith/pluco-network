# VECTOLITH Art Protocol

Open art protocol for Vectolith, designed for Base. Art is the first product surface;
the wider network, wallet and indexer are separate roadmap components. The deployment manifest is stored at `art/deployments/base.json`. CI now verifies its Base mainnet transaction receipts, deployed bytecode, ownership and treasury state, fee settings, supply, mint price, registry status and EIP-2981 royalty configuration through the public Base RPC. All three deployed executable runtimes now match the current Foundry artifacts after compiler metadata and constructor immutable slots are normalized; the immutable supply, mint price and max-per-wallet values are read from chain and checked against the manifest. An internal pre-audit review is recorded in [`docs/SECURITY_REVIEW_NOTES.md`](../docs/SECURITY_REVIEW_NOTES.md); it identifies sale-availability, NFT delivery, admin configuration and collection-attribution risks for remediation or explicit acceptance in a future deployment. It is not an independent audit. Explorer verified-source status and an independent contract security review remain outstanding.

## Contracts (`src/`)

| Contract | Role |
| --- | --- |
| `VectolithRegistry.sol` | Open onchain index of ERC-721 collections. Artist, category, metadata URI, active flag. Holds no art, takes no fee. |
| `VectolithMarketplace.sol` | Non-custodial listings with EIP-2981 royalties and a protocol fee (default 2.5%, hard cap 5%). Pull-payment proceeds. |
| `VectolithOriginals.sol` | Reference collection: 1-of-1 tokens, each with its own metadata URI, immutable supply, provenance hash, owner reserve. |

## Build

```bash
cd contracts
npm install
npm run compile        # writes ABI + bytecode to ./artifacts
```

Compiler: solc 0.8.26, evmVersion cancun, optimizer 200 runs.

## Deploy

Base mainnet only (chain 8453). There is no testnet target in these scripts. This is
a deployment procedure. The manifest records a claimed deployment; verify its transactions and deployed state independently before relying on it:

```bash
PRIVATE_KEY=0x... node deploy-protocol.mjs --fee 250
```

Mainnet gas is real ETH. After deployment, verify the transaction and deployed bytecode,
record the deployer and owner/admin roles, then set the verified addresses on the site.

Fees are native ETH on Base and go to the treasury, which defaults to
`0xcaEC37D3AdcE9a141BF5d78895cb3074Fae77AD9` in both deploy scripts. Set `TREASURY=0x...`
only to override it.

Then deploy a collection if you want the reference one:

```bash
PRIVATE_KEY=0x... node deploy.mjs --supply 100 --price 0.005 --per-wallet 3
```

The scripts print the addresses to set on the site:
`NEXT_PUBLIC_VECTOLITH_REGISTRY`, `NEXT_PUBLIC_VECTOLITH_MARKETPLACE`,
`NEXT_PUBLIC_VECTOLITH_ART_CONTRACT`, `NEXT_PUBLIC_VECTOLITH_CHAIN_ID`.

## Verify the declared Base deployment

Run `bash scripts/verify-base-deployment.sh` from this directory. The script uses the public Base RPC (`https://mainnet.base.org`) without an API key. It checks the eight manifest transactions, expected contract addresses, non-empty deployed bytecode, owner and treasury roles, marketplace registry, configured fees, supply, mint price, active collection registration, mint/list state and the EIP-2981 royalty receiver/rate. The GitHub Actions contract workflow runs this after the Foundry test suite.

These checks confirm current chain state against the manifest. They do not prove that deployed bytecode matches this repository's exact source commit/compiler output, and they are not a substitute for an independent security audit.

## Why Base and not VECTOLITH chain yet

VECTOLITH will be its own OP Stack L2, settling to Ethereum on the same spec Base uses.
Until it has wallets, liquidity and an indexer, art minted there would be invisible.
Base gives distribution today and the contracts are portable to VECTOLITH later, unchanged.
