# PLUCO Network — The NFT Ownership Protocol by Vectolith

[![Build check](https://github.com/vectolith/pluco-network/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/vectolith/pluco-network/actions/workflows/build.yml)
[![Deploy](https://github.com/vectolith/pluco-network/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/vectolith/pluco-network/actions/workflows/deploy.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Live:** Not independently verified. The deployment workflow publishes the static site to this repository's own `gh-pages` branch.

VECTOLITH is an open art market on Base: anyone can register a collection, mint a piece or buy one. This repository is the marketing site and product surface built with Next.js 16 (App Router), React 19, Tailwind CSS 4 and Framer Motion, exported as a fully static site.

PLUCO Network is a Vectolith product and a standalone protocol and marketplace. It owns its website, smart contracts, deployment configuration, treasury and registry controls, and release lifecycle. It does not require VaultETH, Velnor, Blud, Models by Vectolith or any other Vectolith product. Wallet connections and marketplace integrations remain optional and use supported external standards.

## Base contract configuration — chain-state and runtime-bytecode verification passed; source review pending

The site configuration targets Base mainnet (chain ID 8453) and currently contains
these contract addresses:

| Contract | Configured address |
| --- | --- |
| VectolithRegistry | `0x9218b355bb2e69a0f53e072c697e74e1ad63f9ff` |
| VectolithOriginals | `0x1f49c091da217f73493a5b517f490865dbabe15d` |
| VectolithMarketplace | `0x0bbdc74bd7144a32f29196753fd7727995df8e3c` |

The repository includes a deployment manifest at
`contracts/art/deployments/base.json`. It records Base mainnet (chain ID 8453),
the same three addresses shown above, an owner/treasury/royalty receiver, and
transaction hashes for deployment, registration, minting, listing, purchase and
withdrawal. The manifest is repository-supplied evidence. The Foundry CI workflow now independently checks all eight transaction receipts, verifies the three expected contract addresses and non-empty deployed bytecode, and reads current owner/treasury roles, marketplace registry, fee settings, supply, mint price, active registration and EIP-2981 royalty state from the public Base RPC. See [the passing contract verification run](https://github.com/vectolith/pluco-network/actions/runs/44292740465).

The earlier reference to `contracts/deployments/base.json` was a path error;
the actual manifest is under `contracts/art/deployments/base.json`. The
repository also contains contradictory historical deployment statements, so
the current status is **deployment declared; chain-state and normalized runtime-bytecode checks passed on workflow run 44292740465**. Explorer verified-source status and an independent contract security review remain pending. This README does not yet claim verified source, deployed-bytecode
match, or current owner/treasury role confirmation.

Before treating the deployment as fully verified, obtain verified-source status from the explorer and complete an independent contract security review. Keep testnet, local-EVM and mainnet evidence distinct.

`public/config.json` currently points the frontend at the configured addresses.
That setting alone does not establish that live contract reads are valid.

## Tests

65 Foundry tests across the registry, originals and marketplace contracts:

```bash
cd contracts && forge test
```

They cover registration and impersonation rules, the 7.5% royalty and 2.5% fee split,
non-custodial sale re-checks, pull-payment withdrawals, fee caps, and a fuzz test that
the sale split always sums to the price. CI runs the Foundry suite and the public-RPC deployment verification; see
`docs/contracts-ci.md`.

## Deployed V1 and successor proposals

The configured Base contracts are the immutable V1 deployment. Keep the V1 source and deployment manifest aligned with the verified on-chain runtime; do not edit deployed V1 source in place. Security hardening and feature changes belong in separately versioned successor contracts. V2 marketplace and originals proposals are maintained separately and are not deployed or enabled by this repository's current frontend configuration.

## Project structure

```
app/                  Next.js routes (App Router): collections, marketplace, mint, launch, dashboard
components/           Shared UI, including the live gallery and listing views
lib/                  Chain config, onchain reads, Reown setup, content data
contracts/            Foundry project: src, test, script, deployments, vendored lib
contracts/tools ->    compile.mjs, deploy*.mjs (solc-js and ethers path for ABI export)
public/               Static assets and config.json (chain id, contract addresses, Reown id)
docs/                 Fees, remediation history, contract CI notes
scripts/              deploy.sh, the Pages publish wrapper
```

Foundry is the canonical way to compile, test and deploy; the node scripts in
`contracts/` remain for ABI export and ethers-based deploys.

## Features

- **Light and dark themes** driven by `prefers-color-scheme`, no toggle required and no flash on load
- **Wallet connect** on Base mainnet only (chain 8453): MetaMask through EIP-6963 discovery plus WalletConnect for any other EVM wallet, with account change, network switch to Base and disconnect handling. No other chains are configured
- **Responsive** from 360px to wide desktop, with a single shared content frame across pages
- Editorial pages: collections, creators, marketplace, explore, mint, sell, protocol, verification, dashboard, community, brand, about, contact, legal
- SEO: per-page titles, Open Graph and Twitter metadata, canonical URLs, `sitemap.xml` and `robots.txt`

Wallet connection is read-only: it reports the address, network and balance. The frontend uses the addresses in `public/config.json`, but its wallet connection remains read-only; the presence of a deployment manifest does not establish that the frontend can settle transfers.

## Requirements

- Node.js 20 or newer (see `.nvmrc`; CI runs Node 20)
- npm 10 or newer

## Local development

```sh
git clone https://github.com/vectolith/vectolith.git
cd vectolith
npm ci        # exact versions from package-lock.json
npm run dev   # http://localhost:3000
```

To preview with the same base path as production:

```sh
NEXT_PUBLIC_BASE_PATH=/vectolith npm run dev
```

## Build and export

```sh
NEXT_PUBLIC_BASE_PATH=/vectolith npm run build   # prerenders every route into ./out
npx serve out                                # serve the export locally
```

The site uses `output: "export"` in `next.config.ts`, so there is no Node server in production and `npm start` is not part of the deploy path. Any static host works: GitHub Pages, Cloudflare Pages, Netlify, or S3.

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Start the dev server |
| `npm run build` | Static export into `./out` |
| `npm run lint` | Lint |

## Project structure

```
app/          # routes, layout, metadata, sitemap and robots
components/   # navbar, footer, hero, cards, wallet UI, motion helpers
lib/          # data, asset and motion helpers
public/       # static assets
contracts/    # Solidity sources
docs/         # remediation and fee notes
```

## Launching a collection

The site deploys collections itself — no server, no key handling:

1. Open /launch and connect a wallet. It deploys to Base mainnet (chain 8453) only.
2. Set name, symbol, supply, price, per-wallet limit and the mint fee.
3. Sign once. The page shows the address, opens the sale, and prints the config.

The mint page reads addresses from public/config.json at runtime, so a new deployment
only needs that one file updated — no rebuild, no redeploy of the site:

{ "chainId": 8453, "originals": "0x...", "registry": "", "marketplace": "" }

NEXT_PUBLIC_VECTOLITH_ART_CONTRACT and friends still override it at build time. The launch
page encodes the constructor call itself, so the bytecode comes from
public/contracts/VectolithOriginals.json, written by npm run compile in contracts.

### What the contract enforces

- one-of-one tokens, each with its own metadata URI
- price, supply and wallet limit fixed at deploy
- 7.5% EIP-2981 royalty on every resale
- primary mint fee to treasury, hard-capped at 10%
- owner reserve minting without payment

Verified end to end against a local EVM: deploy, sale gate, exact-price check,
per-wallet limit, fee routing to treasury and the royalty maths.

## Deployment

Merging to `main` deploys automatically: `.github/workflows/deploy.yml` builds the static export and publishes `out/` to the `gh-pages` branch, which GitHub Pages serves.

To deploy by hand: `npm run deploy` (builds, then publishes to `gh-pages`). It needs a `gh` login with push access to the repo.

