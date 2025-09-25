;; title: layaway-plans
;; version: 1.0.0
;; summary: Core layaway plan management contract for LayFi
;; description: Manages creation, payments, and completion of tokenized layaway plans

;; traits
;;

;; token definitions
;;

;; constants
;;
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-PLAN-COMPLETED (err u409))
(define-constant ERR-PLAN-CANCELLED (err u410))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u411))
(define-constant ERR-EXCESSIVE-PAYMENT (err u412))
(define-constant ERR-INVALID-DURATION (err u413))
(define-constant ERR-INVALID-MERCHANT (err u414))
(define-constant ERR-WITHDRAWAL-FAILED (err u415))

(define-constant PLAN-STATUS-ACTIVE u1)
(define-constant PLAN-STATUS-COMPLETED u2)
(define-constant PLAN-STATUS-CANCELLED u3)

(define-constant MIN-PLAN-AMOUNT u1000000) ;; 1 STX minimum
(define-constant MAX-PLAN-AMOUNT u100000000000) ;; 100,000 STX maximum
(define-constant MIN-PAYMENT-PERIODS u4) ;; At least 4 payments
(define-constant MAX-PAYMENT-PERIODS u104) ;; Max 2 years weekly
(define-constant CANCELLATION-FEE-PERCENT u5) ;; 5% cancellation fee
(define-constant CONTRACT-FEE-PERCENT u2) ;; 2% service fee

;; data vars
;;
(define-data-var next-plan-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var total-plans-created uint u0)
(define-data-var total-volume-processed uint u0)

;; data maps
;;
(define-map plans
  { plan-id: uint }
  {
    creator: principal,
    merchant: principal,
    target-amount: uint,
    paid-amount: uint,
    payment-periods: uint,
    period-duration: uint,
    created-block: uint,
    status: uint,
    last-payment-block: uint,
    completion-block: (optional uint),
    metadata: (string-ascii 256)
  }
)

(define-map plan-payments
  { plan-id: uint, payment-index: uint }
  {
    amount: uint,
    block-height: uint,
    payer: principal
  }
)

(define-map user-plan-count
  { user: principal }
  { count: uint }
)

(define-map merchant-earnings
  { merchant: principal }
  { total-earned: uint, plans-completed: uint }
)

(define-map plan-payment-index
  { plan-id: uint }
  { current-index: uint }
)

;; public functions
;;

;; Create a new layaway plan
(define-public (create-plan (target-amount uint) (payment-periods uint) (period-duration uint) (merchant principal) (metadata (string-ascii 256)))
  (let (
    (plan-id (var-get next-plan-id))
    (current-block stacks-block-height)
  )
    ;; Validate inputs
    (asserts! (and (>= target-amount MIN-PLAN-AMOUNT) (<= target-amount MAX-PLAN-AMOUNT)) ERR-INVALID-AMOUNT)
    (asserts! (and (>= payment-periods MIN-PAYMENT-PERIODS) (<= payment-periods MAX-PAYMENT-PERIODS)) ERR-INVALID-DURATION)
    (asserts! (> period-duration u0) ERR-INVALID-DURATION)
    (asserts! (not (is-eq merchant tx-sender)) ERR-INVALID-MERCHANT)
    
    ;; Create the plan
    (map-set plans
      { plan-id: plan-id }
      {
        creator: tx-sender,
        merchant: merchant,
        target-amount: target-amount,
        paid-amount: u0,
        payment-periods: payment-periods,
        period-duration: period-duration,
        created-block: current-block,
        status: PLAN-STATUS-ACTIVE,
        last-payment-block: current-block,
        completion-block: none,
        metadata: metadata
      }
    )
    
    ;; Initialize payment index
    (map-set plan-payment-index { plan-id: plan-id } { current-index: u0 })
    
    ;; Update counters
    (var-set next-plan-id (+ plan-id u1))
    (var-set total-plans-created (+ (var-get total-plans-created) u1))
    
    ;; Update user plan count
    (map-set user-plan-count
      { user: tx-sender }
      { count: (+ (get-user-plan-count tx-sender) u1) }
    )
    
    ;; Try to mint plan token
    (match (contract-call? .plan-tokens mint plan-id tx-sender)
      success (ok plan-id)
      error ERR-UNAUTHORIZED
    )
  )
)

;; Make a payment toward a layaway plan
(define-public (make-payment (plan-id uint) (amount uint))
  (let (
    (plan (unwrap! (get-plan plan-id) ERR-NOT-FOUND))
    (current-payment-index (get current-index (unwrap! (map-get? plan-payment-index { plan-id: plan-id }) ERR-NOT-FOUND)))
    (new-paid-amount (+ (get paid-amount plan) amount))
    (remaining-amount (- (get target-amount plan) (get paid-amount plan)))
  )
    ;; Validate payment
    (asserts! (is-eq (get status plan) PLAN-STATUS-ACTIVE) ERR-PLAN-COMPLETED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount remaining-amount) ERR-EXCESSIVE-PAYMENT)
    
    ;; Verify plan ownership through token contract
    (asserts! (is-eq (some tx-sender) (contract-call? .plan-tokens get-owner plan-id)) ERR-UNAUTHORIZED)
    
    ;; Transfer STX to contract for escrow
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Record the payment
    (map-set plan-payments
      { plan-id: plan-id, payment-index: (+ current-payment-index u1) }
      {
        amount: amount,
        block-height: stacks-block-height,
        payer: tx-sender
      }
    )
    
    ;; Update payment index
    (map-set plan-payment-index
      { plan-id: plan-id }
      { current-index: (+ current-payment-index u1) }
    )
    
    ;; Check if plan is now complete
    (if (is-eq new-paid-amount (get target-amount plan))
      ;; Mark as completed
      (begin
        (map-set plans
          { plan-id: plan-id }
          (merge plan {
            paid-amount: new-paid-amount,
            status: PLAN-STATUS-COMPLETED,
            last-payment-block: stacks-block-height,
            completion-block: (some stacks-block-height)
          })
        )
        
        ;; Update merchant earnings
        (let ((merchant-data (default-to { total-earned: u0, plans-completed: u0 }
                                        (map-get? merchant-earnings { merchant: (get merchant plan) }))))
          (map-set merchant-earnings
            { merchant: (get merchant plan) }
            {
              total-earned: (+ (get total-earned merchant-data) (get target-amount plan)),
              plans-completed: (+ (get plans-completed merchant-data) u1)
            }
          )
        )
        
        ;; Update total volume
        (var-set total-volume-processed (+ (var-get total-volume-processed) (get target-amount plan)))
      )
      ;; Update paid amount only
      (map-set plans
        { plan-id: plan-id }
        (merge plan {
          paid-amount: new-paid-amount,
          last-payment-block: stacks-block-height
        })
      )
    )
    
    (ok new-paid-amount)
  )
)

;; Cancel a layaway plan (with fee)
(define-public (cancel-plan (plan-id uint))
  (let (
    (plan (unwrap! (get-plan plan-id) ERR-NOT-FOUND))
    (paid-amount (get paid-amount plan))
    (cancellation-fee (/ (* paid-amount CANCELLATION-FEE-PERCENT) u100))
    (refund-amount (- paid-amount cancellation-fee))
  )
    ;; Validate cancellation
    (asserts! (is-eq (get status plan) PLAN-STATUS-ACTIVE) ERR-PLAN-COMPLETED)
    (asserts! (is-eq (some tx-sender) (contract-call? .plan-tokens get-owner plan-id)) ERR-UNAUTHORIZED)
    
    ;; Mark plan as cancelled
    (map-set plans
      { plan-id: plan-id }
      (merge plan {
        status: PLAN-STATUS-CANCELLED,
        last-payment-block: stacks-block-height
      })
    )
    
    ;; Process refund if any payments were made
    (if (> paid-amount u0)
      (begin
        ;; Transfer refund to user (keep fee for contract)
        (try! (as-contract (stx-transfer? refund-amount tx-sender (get creator plan))))
        (ok refund-amount)
      )
      (ok u0)
    )
  )
)

;; Merchant withdraws funds from completed plan
(define-public (merchant-withdraw (plan-id uint))
  (let (
    (plan (unwrap! (get-plan plan-id) ERR-NOT-FOUND))
    (target-amount (get target-amount plan))
    (service-fee (/ (* target-amount CONTRACT-FEE-PERCENT) u100))
    (merchant-amount (- target-amount service-fee))
  )
    ;; Validate withdrawal
    (asserts! (is-eq (get status plan) PLAN-STATUS-COMPLETED) ERR-PLAN-COMPLETED)
    (asserts! (is-eq tx-sender (get merchant plan)) ERR-UNAUTHORIZED)
    
    ;; Transfer funds to merchant
    (try! (as-contract (stx-transfer? merchant-amount tx-sender (get merchant plan))))
    
    (ok merchant-amount)
  )
)

;; read only functions
;;

;; Get plan details
(define-read-only (get-plan (plan-id uint))
  (map-get? plans { plan-id: plan-id })
)

;; Get plan details with calculated progress
(define-read-only (get-plan-details (plan-id uint))
  (match (get-plan plan-id)
    plan
    (let (
      (progress-percent (if (> (get target-amount plan) u0)
                         (/ (* (get paid-amount plan) u100) (get target-amount plan))
                         u0))
      (remaining-amount (- (get target-amount plan) (get paid-amount plan)))
      (payment-count (get current-index (default-to { current-index: u0 } (map-get? plan-payment-index { plan-id: plan-id }))))
    )
      (ok {
        plan: plan,
        progress-percent: progress-percent,
        remaining-amount: remaining-amount,
        total-payments-made: payment-count
      })
    )
    ERR-NOT-FOUND
  )
)

;; Get payment history for a plan
(define-read-only (get-payment (plan-id uint) (payment-index uint))
  (map-get? plan-payments { plan-id: plan-id, payment-index: payment-index })
)

;; Get user plan count
(define-read-only (get-user-plan-count (user principal))
  (get count (default-to { count: u0 } (map-get? user-plan-count { user: user })))
)

;; Get merchant earnings
(define-read-only (get-merchant-earnings (merchant principal))
  (default-to { total-earned: u0, plans-completed: u0 }
              (map-get? merchant-earnings { merchant: merchant }))
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-plans: (var-get total-plans-created),
    total-volume: (var-get total-volume-processed),
    next-plan-id: (var-get next-plan-id),
    contract-owner: (var-get contract-owner)
  }
)

;; Get plan payment count
(define-read-only (get-plan-payment-count (plan-id uint))
  (get current-index (default-to { current-index: u0 } (map-get? plan-payment-index { plan-id: plan-id })))
)

;; Validate plan ownership
(define-read-only (is-plan-owner (plan-id uint) (user principal))
  (is-eq (some user) (contract-call? .plan-tokens get-owner plan-id))
)

;; Get current plan status
(define-read-only (get-plan-status (plan-id uint))
  (match (get-plan plan-id)
    plan (ok (get status plan))
    ERR-NOT-FOUND
  )
)

;; private functions
;;

;; Calculate recommended payment amount
(define-read-only (calculate-payment-amount (plan-id uint))
  (match (get-plan plan-id)
    plan
    (let (
      (remaining-amount (- (get target-amount plan) (get paid-amount plan)))
      (remaining-periods (- (get payment-periods plan) (get-plan-payment-count plan-id)))
    )
      (if (> remaining-periods u0)
        (ok (/ remaining-amount remaining-periods))
        ERR-PLAN-COMPLETED
      )
    )
    ERR-NOT-FOUND
  )
)

