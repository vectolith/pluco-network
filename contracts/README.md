# VECTOLITH Art Protocol

Contract source and tests for the VECTOLITH digital ownership and provenance product.

**Deployment status: not verified.** The repository's root README explicitly treats the Base contract addresses in `public/config.json` as configuration values, not deployment proof. No canonical deployment record is currently present at the documented path. Do not describe these contracts as deployed, verified, or ready to handle user funds until the deployment evidence below has been independently checked.

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

## Deployment status and release gate

The deployment scripts target Base mainnet (chain ID 8453); they do not provide a testnet target. Mainnet deployment consumes real ETH for gas and must not be run under the current zero-budget constraint or without explicit authorization.

Before any deployment is represented as live, publish and independently verify a canonical deployment record containing:

- chain ID and network;
- each contract address and deployment transaction hash;
- deployer, owner/admin, and treasury addresses read back from chain;
- source commit and compiler/settings;
- verified source status and deployed-bytecode match;
- initialization/configuration state and relevant role checks.

Keep local, testnet, and mainnet evidence separate. Values in `public/config.json` or environment variables are not deployment evidence. Until the gate is complete, the public interface must treat onchain contract functionality as unavailable or unverified.

## Fee and treasury configuration

Fees are native ETH on Base. The deployment scripts contain a default treasury address; review and explicitly authorize the treasury before any deployment. Never place a private key in the repository, CI logs, or public configuration.

## Why Base and not VECTOLITH chain yet

VECTOLITH may later operate its own OP Stack L2, settling to Ethereum on a compatible specification. Until it has wallets, liquidity, and an indexer, deploying art there would make it difficult to discover and use. Base is the current target for a future authorized deployment; portability must be verified rather than assumed.
