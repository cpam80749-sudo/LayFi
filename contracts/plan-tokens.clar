;; title: plan-tokens
;; version: 1.0.0
;; summary: NFT-like tokens representing layaway plan ownership in LayFi
;; description: Manages tokenized ownership and transfers of layaway plans

;; traits
;;

;; token definitions
;;
(define-non-fungible-token plan-token uint)

;; constants
;;
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-NOT-OWNER (err u403))
(define-constant ERR-INVALID-TOKEN-ID (err u400))
(define-constant ERR-TRANSFER-FAILED (err u500))
(define-constant ERR-MINT-FAILED (err u501))
(define-constant ERR-BURN-FAILED (err u502))

(define-constant COLLECTION-NAME "LayFi Plan Tokens")
(define-constant COLLECTION-SYMBOL "LFT")
(define-constant COLLECTION-DESCRIPTION "Tokenized layaway plans for gradual savings toward large purchases")

;; data vars
;;
(define-data-var contract-owner principal tx-sender)
(define-data-var total-supply uint u0)
(define-data-var base-token-uri (string-ascii 256) "https://layfi.app/metadata/")

;; data maps
;;
(define-map token-metadata
  { token-id: uint }
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    image: (string-ascii 256),
    attributes: (string-ascii 512)
  }
)

(define-map authorized-contracts
  { contract: principal }
  { authorized: bool }
)

(define-map token-approvals
  { token-id: uint }
  { approved: principal }
)

(define-map operator-approvals
  { owner: principal, operator: principal }
  { approved: bool }
)

(define-map user-token-count
  { user: principal }
  { count: uint }
)

;; private functions
;;

;; Convert uint to ascii (simplified for small numbers)
(define-read-only (uint-to-ascii (value uint))
  (if (<= value u9)
    (unwrap-panic (element-at "0123456789" value))
    ;; For larger numbers, use a simplified approach
    (if (<= value u99)
      (concat (unwrap-panic (element-at "0123456789" (/ value u10)))
              (unwrap-panic (element-at "0123456789" (mod value u10))))
      ;; For even larger numbers, just use a generic representation
      "999+"
    )
  )
)

;; public functions
;;

;; Mint a new plan token (only called by layaway-plans contract)
(define-public (mint (token-id uint) (recipient principal))
  (let (
    (current-owner (nft-get-owner? plan-token token-id))
  )
    ;; Verify authorization (only layaway-plans contract or owner)
    (asserts! (or (is-authorized-contract contract-caller)
                  (is-eq tx-sender (var-get contract-owner))) ERR-UNAUTHORIZED)
    
    ;; Ensure token doesn't already exist
    (asserts! (is-none current-owner) ERR-ALREADY-EXISTS)
    
    ;; Mint the NFT
    (try! (nft-mint? plan-token token-id recipient))
    
    ;; Update total supply
    (var-set total-supply (+ (var-get total-supply) u1))
    
    ;; Update user token count
    (map-set user-token-count
      { user: recipient }
      { count: (+ (get-user-token-count recipient) u1) }
    )
    
    ;; Set default metadata with proper lengths
    (map-set token-metadata
      { token-id: token-id }
      {
        name: "LayFi Plan",
        description: "A tokenized layaway plan for gradual purchase savings",
        image: "https://layfi.app/metadata/default.json",
        attributes: "{\"plan_id\":\"1\"}"
      }
    )
    
    (ok token-id)
  )
)

;; Transfer a plan token
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (let (
    (current-owner (unwrap! (nft-get-owner? plan-token token-id) ERR-NOT-FOUND))
  )
    ;; Verify ownership and authorization
    (asserts! (or (is-eq tx-sender sender)
                  (is-eq tx-sender current-owner)
                  (is-approved-for-token token-id tx-sender)
                  (is-approved-for-all current-owner tx-sender)) ERR-UNAUTHORIZED)
    
    (asserts! (is-eq sender current-owner) ERR-NOT-OWNER)
    
    ;; Execute transfer
    (try! (nft-transfer? plan-token token-id sender recipient))
    
    ;; Clear any token-specific approvals
    (map-delete token-approvals { token-id: token-id })
    
    ;; Update user token counts
    (map-set user-token-count
      { user: sender }
      { count: (- (get-user-token-count sender) u1) }
    )
    (map-set user-token-count
      { user: recipient }
      { count: (+ (get-user-token-count recipient) u1) }
    )
    
    (ok true)
  )
)

;; Approve another address to transfer a specific token
(define-public (approve (token-id uint) (approved principal))
  (let (
    (current-owner (unwrap! (nft-get-owner? plan-token token-id) ERR-NOT-FOUND))
  )
    ;; Only owner can approve
    (asserts! (is-eq tx-sender current-owner) ERR-NOT-OWNER)
    
    ;; Set approval
    (map-set token-approvals
      { token-id: token-id }
      { approved: approved }
    )
    
    (ok true)
  )
)

;; Approve another address to transfer all tokens owned by sender
(define-public (set-approval-for-all (operator principal) (approved bool))
  (ok (map-set operator-approvals
    { owner: tx-sender, operator: operator }
    { approved: approved }
  ))
)

;; Burn a plan token (when plan is cancelled or completed)
(define-public (burn (token-id uint))
  (let (
    (current-owner (unwrap! (nft-get-owner? plan-token token-id) ERR-NOT-FOUND))
  )
    ;; Only owner or authorized contract can burn
    (asserts! (or (is-eq tx-sender current-owner)
                  (is-authorized-contract contract-caller)
                  (is-eq tx-sender (var-get contract-owner))) ERR-UNAUTHORIZED)
    
    ;; Burn the NFT
    (try! (nft-burn? plan-token token-id current-owner))
    
    ;; Update total supply
    (var-set total-supply (- (var-get total-supply) u1))
    
    ;; Update user token count
    (map-set user-token-count
      { user: current-owner }
      { count: (- (get-user-token-count current-owner) u1) }
    )
    
    ;; Clear metadata and approvals
    (map-delete token-metadata { token-id: token-id })
    (map-delete token-approvals { token-id: token-id })
    
    (ok true)
  )
)

;; Update token metadata (authorized contracts only)
(define-public (update-token-metadata (token-id uint) (name (string-ascii 64)) (description (string-ascii 256)) (attributes (string-ascii 512)))
  (let (
    (current-metadata (get-token-metadata token-id))
  )
    ;; Verify authorization
    (asserts! (or (is-authorized-contract contract-caller)
                  (is-eq tx-sender (var-get contract-owner))) ERR-UNAUTHORIZED)
    
    ;; Verify token exists
    (asserts! (is-some (nft-get-owner? plan-token token-id)) ERR-NOT-FOUND)
    
    ;; Update metadata
    (map-set token-metadata
      { token-id: token-id }
      (merge (unwrap! current-metadata ERR-NOT-FOUND) {
        name: name,
        description: description,
        attributes: attributes
      })
    )
    
    (ok true)
  )
)

;; Authorize a contract to mint/burn tokens (owner only)
(define-public (authorize-contract (contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (map-set authorized-contracts
      { contract: contract }
      { authorized: true }
    )
    (ok true)
  )
)

;; Revoke contract authorization (owner only)
(define-public (revoke-contract-auth (contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (map-delete authorized-contracts { contract: contract })
    (ok true)
  )
)

;; Update base token URI (owner only)
(define-public (set-base-token-uri (new-uri (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set base-token-uri new-uri)
    (ok true)
  )
)

;; Transfer contract ownership (owner only)
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; read only functions
;;

;; Get token owner
(define-read-only (get-owner (token-id uint))
  (nft-get-owner? plan-token token-id)
)

;; Get approved address for token
(define-read-only (get-approved (token-id uint))
  (map-get? token-approvals { token-id: token-id })
)

;; Check if operator is approved for all tokens of owner
(define-read-only (is-approved-for-all (owner principal) (operator principal))
  (default-to false
    (get approved (map-get? operator-approvals { owner: owner, operator: operator })))
)

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata { token-id: token-id })
)

;; Get token URI
(define-read-only (get-token-uri (token-id uint))
  (match (get-token-metadata token-id)
    metadata (ok (get image metadata))
    ERR-NOT-FOUND
  )
)

;; Get total supply
(define-read-only (get-total-supply)
  (var-get total-supply)
)

;; Get user token count
(define-read-only (get-user-token-count (user principal))
  (get count (default-to { count: u0 } (map-get? user-token-count { user: user })))
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Get base token URI
(define-read-only (get-base-token-uri)
  (var-get base-token-uri)
)

;; Get collection information
(define-read-only (get-collection-info)
  {
    name: COLLECTION-NAME,
    symbol: COLLECTION-SYMBOL,
    description: COLLECTION-DESCRIPTION,
    total-supply: (var-get total-supply),
    base-uri: (var-get base-token-uri)
  }
)

;; Check if contract is authorized
(define-read-only (is-authorized-contract (contract principal))
  (default-to false
    (get authorized (map-get? authorized-contracts { contract: contract })))
)

;; Check if address is approved for specific token
(define-read-only (is-approved-for-token (token-id uint) (operator principal))
  (match (get-approved token-id)
    approval-data (is-eq (get approved approval-data) operator)
    false
  )
)

;; Validate token exists
(define-read-only (token-exists (token-id uint))
  (is-some (nft-get-owner? plan-token token-id))
)

;; Get token info with ownership
(define-read-only (get-token-info (token-id uint))
  (match (nft-get-owner? plan-token token-id)
    owner
    (ok {
      owner: owner,
      metadata: (get-token-metadata token-id),
      approved: (get-approved token-id)
    })
    ERR-NOT-FOUND
  )
)

;; Initialize contract with layaway-plans authorization
(begin
  (map-set authorized-contracts
    { contract: .layaway-plans }
    { authorized: true }
  )
)

