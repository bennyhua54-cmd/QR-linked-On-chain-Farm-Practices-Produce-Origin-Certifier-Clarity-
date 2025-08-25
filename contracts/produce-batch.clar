;; produce-batch.clar
;; SIP-009 compatible NFT for produce batches in AgriTrace

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-NOT-FOUND u101)
(define-constant ERR-INVALID-PARAM u102)
(define-constant ERR-ALREADY-EXISTS u103)
(define-constant ERR-NOT-OWNER u104)
(define-constant ERR-PAUSED u105)
(define-constant ERR-INVALID-HARVEST u106)
(define-constant ERR-METADATA-TOO-LONG u107)

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var contract-paused bool false)
(define-data-var token-uri-base (string-ascii 256) "https://agritrace.example/metadata/")
(define-data-var farmer-registry-contract principal 'SP000000000000000000002Q6VF78.farmer-registry) ;; Placeholder
(define-data-var certifier-registry-contract principal 'SP000000000000000000002Q6VF78.certifier-registry) ;; Placeholder

;; Data Maps
(define-map batch-metadata
  uint  ;; token-id
  {
    farmer-principal: principal,
    farmer-id: uint,
    farm-id: uint,
    crop: (string-ascii 16),
    harvest-start: uint,
    harvest-end: uint,
    metadata-hash: (buff 32)
  }
)

(define-map last-log-id uint uint)  ;; token-id => last practice log id
(define-map last-attestation-id uint uint) ;; token-id => last attestation id
(define-map attestations uint (list 100 {certifier: principal, scope: (string-ascii 32), validity-start: uint, validity-end: uint, evidence-hash: (buff 32)}))

;; Non-Fungible Token Definition
(define-non-fungible-token produce-nft uint)

;; Trait Definition for SIP-009
(define-trait nft-trait
  (
    (get-last-token-id () (response uint uint))
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Required Traits
(use-trait farmer-registry-trait .farmer-registry.farmer-registry-trait)
(use-trait certifier-registry-trait .certifier-registry.certifier-registry-trait)

;; Private Functions
(define-private (is-owner (token-id uint) (who principal))
  (match (nft-get-owner? produce-nft token-id)
    owner (is-eq owner who)
    false
  )
)

;; Public Functions

;; Mint a new batch NFT, checking farmer registry
(define-public (mint-batch 
  (farmer-id uint)
  (farm-id uint) 
  (crop (string-ascii 16)) 
  (harvest-start uint) 
  (harvest-end uint) 
  (metadata-hash (buff 32)))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
      (active-res (contract-call? .farmer-registry is-farmer-active farmer-id))
      (principal-res (contract-call? .farmer-registry get-farmer-principal farmer-id))
      (has-farm-res (contract-call? .farmer-registry has-farm farmer-id farm-id))
    )
    (asserts! (not (var-get contract-paused)) (err ERR-PAUSED))
    (try! active-res)
    (asserts! (unwrap! active-res (err ERR-NOT-FOUND)) (err ERR-INACTIVE))
    (try! principal-res)
    (asserts! (is-eq (unwrap! principal-res (err ERR-NOT-FOUND)) tx-sender) (err ERR-NOT-AUTHORIZED))
    (try! has-farm-res)
    (asserts! (unwrap! has-farm-res (err ERR-NOT-FOUND)) (err ERR-INVALID-PARAM))
    (asserts! (> harvest-end harvest-start) (err ERR-INVALID-HARVEST))
    (asserts! (> (len crop) u0) (err ERR-INVALID-PARAM))
    (try! (nft-mint? produce-nft token-id tx-sender))
    (map-set batch-metadata token-id
      {
        farmer-principal: tx-sender,
        farmer-id: farmer-id,
        farm-id: farm-id,
        crop: crop,
        harvest-start: harvest-start,
        harvest-end: harvest-end,
        metadata-hash: metadata-hash
      }
    )
    (map-set last-log-id token-id u0)
    (map-set last-attestation-id token-id u0)
    (map-set attestations token-id (list))
    (var-set last-token-id token-id)
    (print { event: "MINT_BATCH", token-id: token-id, farmer-id: farmer-id, crop: crop })
    (ok token-id)
  )
)

;; Attest batch (certifier only)
(define-public (attest-batch 
  (token-id uint) 
  (scope (string-ascii 32)) 
  (validity-start uint) 
  (validity-end uint) 
  (evidence-hash (buff 32)))
  (let
    (
      (active-res (contract-call? .certifier-registry is-certifier-active tx-sender))
      (has-scope-res (contract-call? .certifier-registry has-scope tx-sender scope))
      (current-attestations (default-to (list) (map-get? attestations token-id)))
      (att-id (+ (default-to u0 (map-get? last-attestation-id token-id)) u1))
    )
    (try! active-res)
    (asserts! (unwrap! active-res (err ERR-NOT-FOUND)) (err ERR-INACTIVE))
    (try! has-scope-res)
    (asserts! (unwrap! has-scope-res (err ERR-NOT-FOUND)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> validity-end validity-start) (err ERR-INVALID-PARAM))
    (let
      (
        (new-attestations (append current-attestations {certifier: tx-sender, scope: scope, validity-start: validity-start, validity-end: validity-end, evidence-hash: evidence-hash}))
      )
      (map-set attestations token-id new-attestations)
      (map-set last-attestation-id token-id att-id)
      (print { event: "ATTEST_BATCH", token-id: token-id, certifier: tx-sender, scope: scope })
      (ok att-id)
    )
  )
)

;; SIP-009 Functions
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat (var-get token-uri-base) (int-to-ascii token-id))))
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? produce-nft token-id))
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-owner token-id sender) (err ERR-NOT-OWNER))
    (nft-transfer? produce-nft token-id sender recipient)
  )
)

;; Read-only for batch details
(define-read-only (get-batch (token-id uint))
  (map-get? batch-metadata token-id)
)

(define-read-only (get-attestations (token-id uint))
  (ok (default-to (list) (map-get? attestations token-id)))
)

;; Admin functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (set-token-uri-base (new-base (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
    (var-set token-uri-base new-base)
    (ok true)
  )
)