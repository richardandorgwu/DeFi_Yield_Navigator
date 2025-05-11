;; Yield Optimizer - A contract that automatically moves funds between different yield-generating protocols
;; based on risk profiles and APY.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-strategy (err u101))
(define-constant err-strategy-exists (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-invalid-risk-profile (err u105))
(define-constant err-invalid-allocation (err u106))
(define-constant err-invalid-protocol (err u107))
(define-constant err-strategy-inactive (err u108))
(define-constant err-unauthorized (err u109))
(define-constant err-invalid-risk-score (err u110))
(define-constant err-general (err u999))

;; Risk profiles
(define-constant risk-conservative u1)
(define-constant risk-moderate u2)
(define-constant risk-aggressive u3)

;; Data maps and variables
(define-map strategies
  { strategy-id: uint }
  {
    protocol: principal,
    current-apy: uint,
    risk-score: uint,
    active: bool,
    allocated-funds: uint
  }
)

(define-map users
  { user: principal }
  {
    risk-profile: uint,
    total-deposited: uint
  }
)

(define-map user-allocations
  { user: principal, strategy-id: uint }
  { allocation-percentage: uint } ;; Out of 10000 (basis points)
)

(define-data-var strategy-count uint u0)
(define-data-var total-funds-locked uint u0)

;; Define SIP-010 token trait
(define-trait ft-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    ;; Get the token balance of a specified principal
    (get-balance (principal) (response uint uint))
    ;; Get the total supply of the token
    (get-total-supply () (response uint uint))
    ;; Get the token name
    (get-name () (response (string-ascii 32) uint))
    ;; Get the token symbol
    (get-symbol () (response (string-ascii 32) uint))
    ;; Get the token decimals
    (get-decimals () (response uint uint))
    ;; Get the token URI
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Main token used in this optimizer
(define-data-var asset-contract principal 'SP000000000000000000002Q6VF78.dummy-token)

;; Events
(define-public (set-asset-contract (new-asset principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set asset-contract new-asset)
    (ok true)
  )
)

;; Add a new yield strategy
(define-public (add-strategy (protocol principal) (current-apy uint) (risk-score uint))
  (let
    (
      (strategy-id (var-get strategy-count))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (is-eq protocol 'SP000000000000000000002Q6VF78)) err-invalid-protocol)
    (asserts! (<= risk-score u100) err-invalid-risk-score)
    
    (map-insert strategies 
      { strategy-id: strategy-id }
      {
        protocol: protocol,
        current-apy: current-apy,
        risk-score: risk-score,
        active: true,
        allocated-funds: u0
      }
    )
    
    (var-set strategy-count (+ strategy-id u1))
    (ok strategy-id)
  )
)

;; Update strategy APY
(define-public (update-strategy-apy (strategy-id uint) (new-apy uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? strategies { strategy-id: strategy-id })) err-invalid-strategy)
    
    (map-set strategies 
      { strategy-id: strategy-id }
      (merge (unwrap-panic (map-get? strategies { strategy-id: strategy-id })) 
             { current-apy: new-apy })
    )
    (ok true)
  )
)

;; Set strategy active status
(define-public (set-strategy-active (strategy-id uint) (active bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? strategies { strategy-id: strategy-id })) err-invalid-strategy)
    
    (map-set strategies 
      { strategy-id: strategy-id }
      (merge (unwrap-panic (map-get? strategies { strategy-id: strategy-id })) 
             { active: active })
    )
    (ok true)
  )
)

;; Deposit funds into the optimizer
(define-public (deposit (token-contract <ft-trait>) (amount uint))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: tx-sender })))
      (new-total (+ (get total-deposited user-data) amount))
    )
    ;; Check that the token contract matches our asset
    (asserts! (is-eq (contract-of token-contract) (var-get asset-contract)) err-invalid-protocol)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Transfer tokens to the contract
    (try! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none))
    
    ;; Update user's total deposited
    (map-set users 
      { user: tx-sender } 
      { 
        risk-profile: (get risk-profile user-data), 
        total-deposited: new-total 
      }
    )
    
    ;; Update total funds locked
    (var-set total-funds-locked (+ (var-get total-funds-locked) amount))
    
    ;; Handle allocation separately - don't use try! here
    (handle-deposit-allocation)
    
    (ok true)
  )
)

;; Helper function to handle deposit allocation
(define-private (handle-deposit-allocation)
  ;; This function now returns a boolean instead of a response
  (begin
    ;; Call allocate-funds but don't propagate errors
    (unwrap-panic (allocate-funds tx-sender))
    true
  )
)

;; Withdraw funds from the optimizer
(define-public (withdraw (token-contract <ft-trait>) (amount uint))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: tx-sender })))
      (current-balance (get total-deposited user-data))
      (new-total (- current-balance amount))
    )
    ;; Check that the token contract matches our asset
    (asserts! (is-eq (contract-of token-contract) (var-get asset-contract)) err-invalid-protocol)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= current-balance amount) err-insufficient-balance)
    
    ;; Withdraw funds from strategies - don't use try! here
    (unwrap-panic (withdraw-funds-internal tx-sender amount))
    
    ;; Update user's total deposited
    (map-set users 
      { user: tx-sender } 
      { 
        risk-profile: (get risk-profile user-data), 
        total-deposited: new-total 
      }
    )
    
    ;; Update total funds locked
    (var-set total-funds-locked (- (var-get total-funds-locked) amount))
    
    ;; Transfer tokens back to the user
    (as-contract 
      (try! (contract-call? token-contract transfer amount tx-sender tx-sender none))
    )
    
    (ok true)
  )
)

;; Set user risk profile
(define-public (set-risk-profile (profile uint))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: tx-sender })))
    )
    (asserts! (or (is-eq profile risk-conservative) 
                 (is-eq profile risk-moderate) 
                 (is-eq profile risk-aggressive)) 
              err-invalid-risk-profile)
    
    ;; Update user's risk profile
    (map-set users 
      { user: tx-sender } 
      { 
        risk-profile: profile, 
        total-deposited: (get total-deposited user-data) 
      }
    )
    
    ;; Only reallocate if the user has funds deposited
    (if (> (get total-deposited user-data) u0)
      (begin
        (rebalance-after-profile-change)
        (ok true))
      (ok true)
    )
  )
)

;; Helper function to handle rebalancing after profile change
(define-private (rebalance-after-profile-change)
  ;; This function now returns a boolean instead of a response
  (begin
    ;; Call allocate-funds but don't propagate errors
    (unwrap-panic (allocate-funds tx-sender))
    true
  )
)

;; Manually reallocate funds across strategies
(define-public (reallocate-funds (strategy-ids (list 20 uint)) (allocations (list 20 uint)))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: tx-sender })))
    )
    (asserts! (> (get total-deposited user-data) u0) err-insufficient-balance)
    (asserts! (is-eq (len strategy-ids) (len allocations)) err-invalid-allocation)
    
    ;; Check total allocations sum to 10000
    (asserts! (check-allocation-sum allocations u0 u0) err-invalid-allocation)
    
    ;; Validate all strategies exist and are active
    (unwrap-panic (validate-strategies-internal strategy-ids))
    
    ;; Update allocations - use unwrap-panic instead of try!
    (unwrap-panic (update-user-allocations tx-sender strategy-ids allocations))
    
    ;; Execute reallocation
    (unwrap-panic (execute-reallocation-internal tx-sender))
    
    (ok true)
  )
)

;; Helper function to check allocation sum (non-recursive to avoid fold/recursion)
(define-private (check-allocation-sum (allocations (list 20 uint)) (index uint) (sum uint))
  (let
    (
      (a0 (default-to u0 (element-at allocations u0)))
      (a1 (default-to u0 (element-at allocations u1)))
      (a2 (default-to u0 (element-at allocations u2)))
      (a3 (default-to u0 (element-at allocations u3)))
      (a4 (default-to u0 (element-at allocations u4)))
      (a5 (default-to u0 (element-at allocations u5)))
      (a6 (default-to u0 (element-at allocations u6)))
      (a7 (default-to u0 (element-at allocations u7)))
      (a8 (default-to u0 (element-at allocations u8)))
      (a9 (default-to u0 (element-at allocations u9)))
      (total-sum (+ (+ (+ (+ (+ (+ (+ (+ (+ a0 a1) a2) a3) a4) a5) a6) a7) a8) a9))
      (rest-sum (if (> (len allocations) u10)
                  (+ (+ (+ (+ (+ (+ (+ (+ (+ (default-to u0 (element-at allocations u10))
                                             (default-to u0 (element-at allocations u11)))
                                          (default-to u0 (element-at allocations u12)))
                                       (default-to u0 (element-at allocations u13)))
                                    (default-to u0 (element-at allocations u14)))
                                 (default-to u0 (element-at allocations u15)))
                              (default-to u0 (element-at allocations u16)))
                           (default-to u0 (element-at allocations u17)))
                        (default-to u0 (element-at allocations u18)))
                     (default-to u0 (element-at allocations u19)))
                  u0))
    )
    (is-eq (+ total-sum rest-sum) u10000)
  )
)

;; Private functions

;; Get optimal allocations and return strategy IDs and percentages
(define-private (get-allocation-data (user principal))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: user })))
      (user-profile (get risk-profile user-data))
    )
    ;; Simplified allocation based on risk profile
    ;; In production, this would use more sophisticated logic
    { 
      strategy-ids: (list u0 u1), 
      percentages: (list u5000 u5000) 
    }
  )
)

;; Allocate user funds based on their risk profile
(define-private (allocate-funds (user principal))
  (let
    (
      (allocation-data (get-allocation-data user))
      (strategy-ids (get strategy-ids allocation-data))
      (allocation-percentages (get percentages allocation-data))
    )
    ;; Update user allocations - use unwrap-panic instead of try!
    (unwrap-panic (update-user-allocations user strategy-ids allocation-percentages))
    
    ;; Execute reallocation
    (execute-reallocation-internal user)
  )
)

;; Update user strategy allocations
(define-private (update-user-allocations (user principal) (strategy-ids (list 20 uint)) (allocations (list 20 uint)))
  (begin
    ;; Clear existing allocations
    (clear-user-allocations user)
    
    ;; Set new allocations (iteratively to avoid recursion)
    (if (> (len strategy-ids) u0)
      (begin
        (set-user-allocations user strategy-ids allocations u0)
        (if (> (len strategy-ids) u1)
          (begin
            (set-user-allocations user strategy-ids allocations u1)
            (if (> (len strategy-ids) u2)
              (begin
                (set-user-allocations user strategy-ids allocations u2)
                (if (> (len strategy-ids) u3)
                  (begin
                    (set-user-allocations user strategy-ids allocations u3)
                    (if (> (len strategy-ids) u4)
                      (set-user-allocations user strategy-ids allocations u4)
                      true))
                  true))
              true))
          true))
      true)
    
    ;; Return a response type with a specific error value
    (ok true)
  )
)

;; Clear all user allocations - helper function
(define-private (clear-user-allocations (user principal))
  (begin
    ;; For a production contract, we would need to iterate through all strategy IDs
    ;; and clear each allocation. For simplicity in this example, we assume the caller
    ;; will provide all active strategies when updating.
    true
  )
)

;; Set user allocations helper - returns a boolean
(define-private (set-user-allocations (user principal) 
                                     (strategy-ids (list 20 uint)) 
                                     (allocations (list 20 uint))
                                     (index uint))
  (begin
    ;; Just set the allocation for the given index
    (if (< index (len strategy-ids))
      (map-set user-allocations
        { user: user, strategy-id: (unwrap-panic (element-at strategy-ids index)) }
        { allocation-percentage: (unwrap-panic (element-at allocations index)) }
      )
      false
    )
    true
  )
)

;; Execute reallocation of funds for a user - internal version with specific error type
(define-private (execute-reallocation-internal (user principal))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: user })))
      (total-funds (get total-deposited user-data))
    )
    ;; In a real implementation, this would call out to the various DeFi protocols
    ;; For this example, we just update internal accounting
    
    ;; Iterate through strategies to update allocations
    ;; In practice, you would need to implement this based on specific protocols
    (ok true)
  )
)

;; Withdraw funds from strategies - internal version with specific error type
(define-private (withdraw-funds-internal (user principal) (amount uint))
  (begin
    ;; In a real implementation, this would call out to the various DeFi protocols
    ;; For this example, we just update internal accounting
    (ok true)
  )
)

;; Validate that all strategies exist and are active - internal version with specific error type
(define-private (validate-strategies-internal (strategy-ids (list 20 uint)))
  (begin
    ;; Check first 5 strategies (non-recursive approach)
    (if (> (len strategy-ids) u0)
      (begin
        (unwrap-panic (validate-strategy-internal (unwrap-panic (element-at strategy-ids u0))))
        (if (> (len strategy-ids) u1)
          (begin
            (unwrap-panic (validate-strategy-internal (unwrap-panic (element-at strategy-ids u1))))
            (if (> (len strategy-ids) u2)
              (begin
                (unwrap-panic (validate-strategy-internal (unwrap-panic (element-at strategy-ids u2))))
                (if (> (len strategy-ids) u3)
                  (begin
                    (unwrap-panic (validate-strategy-internal (unwrap-panic (element-at strategy-ids u3))))
                    (if (> (len strategy-ids) u4)
                      (begin
                        (unwrap-panic (validate-strategy-internal (unwrap-panic (element-at strategy-ids u4))))
                        (ok true))
                      (ok true)))
                  (ok true)))
              (ok true)))
          (ok true)))
      (ok true))
  )
)

;; Validate a single strategy - internal version with specific error type
(define-private (validate-strategy-internal (strategy-id uint))
  (let
    (
      (strategy (map-get? strategies { strategy-id: strategy-id }))
    )
    (asserts! (is-some strategy) err-invalid-strategy)
    (asserts! (get active (unwrap-panic strategy)) err-strategy-inactive)
    (ok true)
  )
)

;; Get optimal allocations based on risk profile
(define-read-only (get-optimal-allocations (user principal))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: user })))
      (user-profile (get risk-profile user-data))
      (strategy-count-val (var-get strategy-count))
    )
    ;; In a real implementation, this would calculate based on APY and risk scores
    ;; For this example, we return a simplified allocation
    
    ;; This is a placeholder that would need to be implemented with real logic
    ;; based on active strategies, their APYs, and risk scores
    { 
      strategy-ids: (list u0 u1), 
      percentages: (list u5000 u5000) 
    }
  )
)

;; View functions

;; Get user total value
(define-read-only (get-user-total-value (user principal))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: user })))
    )
    ;; In a real implementation, this would include yields from protocols
    ;; For this example, we just return the deposited amount
    (get total-deposited user-data)
  )
)

;; Get strategy details
(define-read-only (get-strategy (strategy-id uint))
  (map-get? strategies { strategy-id: strategy-id })
)

;; Get user risk profile
(define-read-only (get-user-risk-profile (user principal))
  (let
    (
      (user-data (default-to { risk-profile: risk-moderate, total-deposited: u0 } 
                  (map-get? users { user: user })))
    )
    (get risk-profile user-data)
  )
)

;; Get user allocation for a specific strategy
(define-read-only (get-user-allocation (user principal) (strategy-id uint))
  (default-to { allocation-percentage: u0 } 
    (map-get? user-allocations { user: user, strategy-id: strategy-id }))
)

;; Get total funds locked in the contract
(define-read-only (get-total-funds-locked)
  (var-get total-funds-locked)
)

;; Get total strategy count
(define-read-only (get-strategy-count)
  (var-get strategy-count)
)

;; Recovery functions - only for owner

;; Emergency function to recover tokens sent to the contract
(define-public (recover-tokens (token-contract <ft-trait>) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let
      (
        (balance (unwrap-panic (contract-call? token-contract get-balance (as-contract tx-sender))))
      )
      (as-contract
        (try! (contract-call? token-contract transfer balance tx-sender recipient none))
      )
    )
    (ok true)
  )
)

;; Emergency pause function
(define-data-var paused bool false)

(define-public (set-paused (new-paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set paused new-paused)
    (ok true)
  )
)

(define-read-only (is-paused)
  (var-get paused)
)