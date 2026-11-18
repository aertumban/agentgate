# AgentGate — the Agent ID holders' clubhouse on BNB Chain

AgentGate turns an **Agent ID** (`name.ai`, the on-chain identity of a Binance
Agentic Wallet) into a working key. If your wallet holds an Agent ID, you are
in. If it doesn't, nothing in this contract is available to you.

Built for the **Binance Wallet × BNB Chain Agent ID Hackathon** (2026).

## What it does

1. **Soulbound badge.** Every Agent ID holder can claim one AgentGate Badge
   (ERC-721, non-transferable). One badge per address, forever tied to the
   wallet that claimed it — like the Agent ID itself.
2. **Daily check-ins & streaks.** Badge holders check in once per UTC day.
   Consecutive days build a streak; the badge's on-chain metadata
   (`tokenURI`, a base64 JSON data URI generated entirely on-chain) levels up
   with the holder's current streak, best streak, and total check-ins.
3. **Holder-to-holder invites.** A claim can name an inviter — another
   holder's address — recorded publicly on-chain, so the club grows through
   its own members.

## How Agent ID is integrated

The contract reads the official SPACE ID Agent ID registry on BNB Chain
(`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) directly:

- `claimBadge` requires `registry.balanceOf(msg.sender) > 0`.
- `checkIn` **re-verifies** the holder on every call — the gate is live, not
  a one-time check. If an address no longer holds an Agent ID, it can no
  longer check in.

Agent ID is not a cosmetic filter here; it is the product's entire access
layer, identity record, and growth mechanic.

## Contract

| | |
|---|---|
| Network | BNB Chain (56) |
| AgentGate | `0x84dc4A6972aE91946F7c852c3Bbe7bc09F0f0b0e` |
| Deploy tx | `0xae4abe7d9d27d43c29def72090c1dc73c6c5e2e62220c79545d6f8266edd3440` |
| Deployed via | Arachnid CREATE2 factory (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) from the project's Agentic Wallet |
| Source verification | Sourcify exact match (creation + runtime) — see the contract page |

## Safety properties (by construction)

- **No owner, no admin keys.** The registry address is immutable; there is
  no pause, upgrade, mint switch, or fee function.
- **No funds.** Every function is non-payable; the contract never holds or
  moves user assets. Claiming and checking in cost only network gas.
- **No approvals.** The contract never asks users for token approvals.
- **Soulbound means soulbound.** Every transfer and approval path reverts.
- **No return promises.** The badge is a club membership record, nothing
  more. It is not an investment and promises no yield of any kind.

## Run it locally

```bash
npm install
npm run compile   # solc 0.8.26, viaIR, evmVersion paris, optimizer 200
npm test          # ganache + ethers suite: gate, claims, streaks, soulbound
```

`contracts/MockAgentID.sol` is a test-only stand-in for the registry and is
never deployed to mainnet.

## License

MIT
