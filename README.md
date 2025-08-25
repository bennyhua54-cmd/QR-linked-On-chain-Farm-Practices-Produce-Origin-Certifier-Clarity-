# AgriTrace — QR‑linked, On‑chain Farm Practices & Produce Origin Certifier (Clarity)

A real‑world Web3 system for agriculture that anchors farm practice logs, certifies produce origin, and lets anyone scan a QR code to verify provenance on the Stacks blockchain (Bitcoin‑secured). Built around **3–5 focused Clarity smart contracts**, production‑minded data models, and an auditable workflow farmers and certifiers can actually use.

---

## Why AgriTrace?

**Problem.** Food buyers (exporters, retailers, consumers) struggle to verify:

* Who grew this? Where and when?
* What farming practices were used (e.g., pesticide applications, organic inputs, irrigation events)?
* Is the “organic / GAP / fair trade” claim actually certified?

**Solution.** AgriTrace turns each produce batch into a verifiable on‑chain asset. Farmers append **tamper‑evident practice logs**; accredited certifiers issue **digitally signed origin & practice attestations**; supply‑chain handlers add custody checkpoints. A **QR code** on a crate maps to a canonical on‑chain identifier anyone can read in a block explorer.

---

## Contract Set (3–5 solid Clarity contracts)

You can deploy 4 contracts for a lean MVP (or include #5 for advanced custody):

1. **`farmer-registry.clar`** — KYC/attestation‑backed farmer identities and farms (fields/plots).
2. **`certifier-registry.clar`** — Role‑gated registry of accredited certification bodies/inspectors.
3. **`produce-batch.clar`** — SIP‑009‑compatible NFT representing each harvest/lot; embeds immutable origin metadata; links to logs/certs.
4. **`practice-log.clar`** — Append‑only, hash‑anchored log entries (practice type, timestamp, geo, evidence hash).
5. *(Optional)* **`supply-chain.clar`** — Custody checkpoints, transfers, and condition readings (e.g., cold‑chain hashes).

> **Stacks/Clarity**: Deterministic, interpreted smart contracts secured by Bitcoin via Stacks. Use [Clarinet] for dev/test.

---

## Architecture Overview

```
+------------------------+        +-------------------------+
| Mobile/Web App         |        | Certifier Portal        |
| - Create batches (QR)  |        | - Verify farmer         |
| - Append practice logs |<-----> | - Issue attestations    |
| - Scan & verify        |        | - Revoke if needed      |
+-----------+------------+        +------------+------------+
            |                                  |
            v                                  v
      +-----+----------------------------------+-----+
      |             Stacks / Clarity Contracts       |
      | 1) farmer-registry   2) certifier-registry   |
      | 3) produce-batch     4) practice-log         |
      | 5) supply-chain (opt)                        |
      +---------+---------------+--------------------+
                |               |
                v               v
       Off-chain evidence   QR on crates/labels ->
       (PDFs, images,       stx:<asset-id>#<token-id>
        lab results)        + optional deep link
```

---

## QR Code Schema

Each physical label encodes a canonical, chain‑native address that wallets and block explorers can resolve:

```
stx://asset/SPXXXX.produce-batch::produce-nft?token-id=<u128>
```

**Recommended fields in the QR payload (JSON inside a URI or simply query params):**

* `asset` — contract asset identifier (`SPxxx.produce-batch::produce-nft`)
* `tokenId` — unique batch token id
* `batchHash` — sha256 of immutable metadata blob used at mint
* `view` — explorer deep link (e.g., `https://explorer.hiro.so/txid/...`)

> The QR is *not* the source of truth—on‑chain state is. If QR is damaged/spoofed, the token id + asset resolves provenance.

---

## Data Model & Sources of Truth

### `farmer-registry.clar`

* **Maps**: `farmers` → struct `{ active: bool, metadata-hash: (buff 32), farms: (list ...) }`
* **Concepts**: A “farmer” principal, plus 0..n farms/plots (geo hash + human label). Optional DID reference off‑chain.

### `certifier-registry.clar`

* **Maps**: `certifiers` → struct `{ active: bool, name-hash: (buff 32), scopes: (list 10 (string-ascii 32)) }`
* **Authority**: contract owner (DAO multisig or governance) manages admissions/suspensions.

### `produce-batch.clar`

* **Asset**: SIP‑009 NFT `produce-nft` (token‑id: `uint`)
* **Immutable at mint**: origin farm id, crop code, harvest window, seed/variety, metadata hash (IPFS/Arweave), farmer principal
* **Mutable pointers**: last practice log id, last certificate id (for quick lookup)

### `practice-log.clar`

* **Append‑only**: `logs` map `token-id => list (up to N) of log-ids`; `log-entries` map `log-id => struct`
* **Entry**: `type`, `occurred-at` (unix), `geo-hash`, `evidence-hash`, `actor` (principal), `version`

### `supply-chain.clar` (optional)

* **Checkpoints**: custody transfers `(from -> to)`, condition hashes (e.g., temp logger file hash), location/time.

---

## Contract APIs (selected)

> **Note**: Clarity is typed & interpreted; below are representative function shapes, *not* drop‑in code.

### 1) `farmer-registry.clar`

* `((register-farmer (metadata-hash (buff 32))) (response uint uint))` → returns `farmer-id`
* `((add-farm (farmer-id uint) (geo-hash (buff 16)) (label (string-ascii 64))) (response uint uint))`
* `((deactivate-farmer (farmer-id uint)) (response bool uint))`
* **Auth**: `tx-sender` self‑service for register; owner‑only for force‑deactivate.

### 2) `certifier-registry.clar`

* `((add-certifier (who principal) (name-hash (buff 32)) (scopes (list 10 (string-ascii 32)))) (response bool uint))`
* `((deactivate-certifier (who principal)) (response bool uint))`
* `((is-active (who principal)) (response bool uint))`

### 3) `produce-batch.clar` (SIP‑009)

* `((mint-batch (farmer-id uint) (farm-id uint) (crop (string-ascii 16)) (harvest-start uint) (harvest-end uint) (metadata-hash (buff 32))) (response uint uint))`
* `((get-batch (token-id uint)) (response { farmer-id: uint, farm-id: uint, crop: (string-ascii 16), harvest: {start: uint, end: uint}, metadata-hash: (buff 32), farmer: principal } uint))`
* SIP‑009 required: `transfer`, `get-owner?`, `get-total-supply`, `get-token-uri` (optional)

### 4) `practice-log.clar`

* `((append-log (token-id uint) (typ (string-ascii 24)) (occurred-at uint) (geo-hash (buff 16)) (evidence-hash (buff 32))) (response uint uint))` → returns `log-id`
* `((get-logs (token-id uint) (offset uint) (limit uint)) (response (list 50 uint) uint))`
* **Auth**: only current owner of `token-id` (farmer or custodian) or whitelisted operator may append.

### 5) `supply-chain.clar`

* `((transfer-custody (token-id uint) (to principal) (checkpoint-hash (buff 32))) (response bool uint))`
* `((get-custody (token-id uint)) (response (list 100 {holder: principal, at: uint, checkpoint-hash: (buff 32)}) uint))`

**Errors** (illustrative):

* `ERR-NOT-AUTHORIZED = u100`, `ERR-NOT-FOUND = u101`, `ERR-NOT-ACTIVE = u102`, `ERR-INVALID-STATE = u103`.

**Events/Logs**: Use `(print ...)` to emit structured JSON for indexers (e.g., `{event: "MINT", token-id: u123, farmer: 'SP...'}`).

---

## Roles & Authorization

* **Contract Owner/Governance**: manages certifier list; can pause specific functions (emergency circuit breaker).
* **Farmers**: register; mint batches; append logs; optionally delegate to operators.
* **Certifiers** (from `certifier-registry`): issue attestations (via dedicated calls on `produce-batch` or separate `attestation` map), revoke if necessary.
* **Custodians/Handlers**: if optional custody is enabled, they can receive/transfer custody and append condition checkpoints.
* **Public (read‑only)**: anyone resolves a QR to read immutable batch origin + logs + cert state.

---

## End‑to‑End Flow

1. **Onboard**: Farmer calls `register-farmer`; governance adds certifier(s).
2. **Mint batch**: Farmer harvests → calls `mint-batch` → returns `token-id`.
3. **Label**: Off‑chain service creates a QR that encodes asset id + token id (+ explorer deep link).
4. **Practice logging**: As activities occur or are documented, append entries with evidence hashes (e.g., lab PDF on IPFS).
5. **Certification**: Certifier portal calls `attest-batch` on `produce-batch` (or a sub‑map) linking scope, validity window, and evidence hash.
6. **(Optional) Custody**: Handlers `transfer-custody` and attach checkpoint hashes (e.g., cold‑chain logger).
7. **Scan & Verify**: Buyer scans QR → app resolves on‑chain batch, logs, attestations; compares local evidence hashes to public hashes.

---

## Off‑chain Evidence Strategy

* **Content‑addressed storage**: IPFS/Arweave for large proofs (PDFs, photos, sensor CSVs). Store only **sha256** on‑chain.
* **PII hygiene**: redact PII from public blobs; or encrypt & share keys privately (hash of ciphertext still anchors integrity).
* **Time‑ordering**: use block height + unix time in logs to show sequence.

---

## Dev Setup & Deployment (Clarinet)

### Prereqs

* [Clarinet] ≥ v1.7, Node.js ≥ 18, Rust toolchain (for Clarinet)
* Stacks testnet/mainnet access (Hiro wallet or private key via `.env`)

### Quickstart

```bash
# 1) Create project
clarinet new agritrace && cd agritrace

# 2) Add contracts (paths shown)
# contracts/farmer-registry.clar
# contracts/certifier-registry.clar
# contracts/produce-batch.clar
# contracts/practice-log.clar
# contracts/supply-chain.clar   # optional

# 3) Configure deployments
# Clarinet.toml → [contracts] + [repl.deployments]

# 4) Test
clarinet test

# 5) Console (manual calls)
clarinet console
```

**Environment variables**: use `.env` to store deployer keys; avoid committing secrets.

### Suggested Test Cases

* Can register farmer; cannot mint batch if farmer inactive.
* Certifier must be active to attest; revocation flips status.
* Only owner/operator can append logs; append is strictly monotonic.
* Custody transfer requires current holder; history is consistent.
* QR token id resolves to correct batch, immutable metadata hash matches.

---

## Example: Minimal Function Signatures (snippets)

```clarity
;; --- certifier-registry.clar ---
(define-constant ERR-NOT-AUTHORIZED u100)
(define-data-var owner principal tx-sender)
(define-map certifiers principal bool)

(define-read-only (is-active (who principal))
  (default-to false (map-get? certifiers who)))

(define-public (add-certifier (who principal))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) ERR-NOT-AUTHORIZED)
    (map-set certifiers who true)
    (ok true)))
```

```clarity
;; --- practice-log.clar ---
(define-constant ERR-NOT-AUTHORIZED u100)
(define-trait sip009-nft-trait
  (
    (transfer (uint principal principal) (response bool uint))
    (get-owner? (uint) (response (optional principal) uint))
  )
)
(define-read-only (is-owner (nft <sip009-nft-trait>) (token-id uint) (who principal))
  (match (contract-call? nft get-owner? token-id)
    owner (ok (is-some owner) (is-eq (unwrap! owner (err u0)) who))
    err   (ok false)))
```

> Full contracts are provided in `/contracts` when you scaffold (see next section).

---

## Project Structure

```
agritrace/
├─ Clarinet.toml
├─ contracts/
│  ├─ farmer-registry.clar
│  ├─ certifier-registry.clar
│  ├─ produce-batch.clar
│  ├─ practice-log.clar
│  └─ supply-chain.clar   # optional
├─ tests/
│  ├─ produce-batch_test.ts
│  ├─ practice-log_test.ts
│  └─ e2e_traceability_test.ts
├─ app/                    # optional web portal / mobile
│  ├─ README.md
│  └─ ...
└─ README.md
```

---

## Security, Fraud & Privacy Considerations

* **Copy‑paste / QR spoofing**: QR only aids discovery; verify on‑chain owner + certifier signature + `metadata-hash`.
* **Sybil farmers/certifiers**: strong onboarding off‑chain; certifier registry gated by governance.
* **Log integrity**: append‑only with ever‑increasing `log-id`; indexer can reject out‑of‑order timestamps.
* **Revocation**: certifiers can revoke attestations; UI surfaces revocation block and reason.
* **PII**: never store PII/plaintext locations if restricted; use geo‑hash precision reduction.

---

## Explorer & UX

* Clicking a QR link opens a public batch page that:

  * Loads NFT owner, farmer profile, origination farm, harvest window
  * Streams practice logs and cert statuses
  * Compares client‑fetched evidence files to on‑chain hashes

---

## Roadmap (optional extensions)

* **DAO governance** for certifier registry via voting contract
* **Sensor oracles**: anchor signed IoT payload hashes (temp/humidity)
* **Marketplace hooks**: allow escrowed sales triggered by certification state
* **ZK attestations**: privacy‑preserving proof of compliance

---

## Licensing

MIT for the code; content © your organization. Replace as needed.

---

## Attribution & References

* Stacks / Clarity docs
* SIP‑009 Non‑Fungible Token standard
* Clarinet developer tooling

[Clarinet]: https://github.com/hirosystems/clarinet
