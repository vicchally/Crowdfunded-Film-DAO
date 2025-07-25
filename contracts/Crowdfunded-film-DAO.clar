(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_DEADLINE_PASSED (err u104))
(define-constant ERR_FUNDING_NOT_COMPLETE (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))

(define-data-var next-film-id uint u0)
(define-data-var next-reward-id uint u0)

(define-map films
  { film-id: uint }
  {
    creator: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    funding-goal: uint,
    funding-raised: uint,
    deadline: uint,
    is-funded: bool,
    reward-distribution: bool
  }
)

(define-map film-backers
  { film-id: uint, backer: principal }
  { amount: uint, reward-tier: uint }
)

(define-map backer-votes
  { film-id: uint, voter: principal }
  { vote-weight: uint, timestamp: uint }
)

(define-map reward-claims
  { reward-id: uint }
  {
    film-id: uint,
    recipient: principal,
    reward-type: (string-ascii 32),
    claimed: bool,
    metadata: (string-ascii 128)
  }
)

(define-map film-voting-power
  { film-id: uint }
  { total-votes: uint, voting-deadline: uint }
)

(define-public (create-film (title (string-ascii 64)) (description (string-ascii 256)) (funding-goal uint) (days-to-deadline uint))
  (let 
    (
      (film-id (var-get next-film-id))
      (deadline (+ stacks-block-height (* days-to-deadline u144)))
    )
    (asserts! (> funding-goal u0) ERR_INVALID_AMOUNT)
    (asserts! (> days-to-deadline u0) ERR_INVALID_AMOUNT)
    
    (map-set films
      { film-id: film-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        funding-goal: funding-goal,
        funding-raised: u0,
        deadline: deadline,
        is-funded: false,
        reward-distribution: false
      }
    )
    
    (map-set film-voting-power
      { film-id: film-id }
      { total-votes: u0, voting-deadline: (+ deadline u1440) }
    )
    
    (var-set next-film-id (+ film-id u1))
    (ok film-id)
  )
)

(define-public (fund-film (film-id uint) (amount uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (current-backing (default-to { amount: u0, reward-tier: u0 } (map-get? film-backers { film-id: film-id, backer: tx-sender })))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= stacks-block-height (get deadline film-data)) ERR_DEADLINE_PASSED)
    (asserts! (not (get is-funded film-data)) ERR_ALREADY_EXISTS)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (let 
      (
        (new-raised (+ (get funding-raised film-data) amount))
        (new-backing-amount (+ (get amount current-backing) amount))
        (reward-tier (calculate-reward-tier new-backing-amount))
      )
      (map-set films
        { film-id: film-id }
        (merge film-data { 
          funding-raised: new-raised,
          is-funded: (>= new-raised (get funding-goal film-data))
        })
      )
      
      (map-set film-backers
        { film-id: film-id, backer: tx-sender }
        { amount: new-backing-amount, reward-tier: reward-tier }
      )
      
      (ok true)
    )
  )
)

(define-public (vote-on-film (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: film-id, backer: tx-sender }) ERR_UNAUTHORIZED))
      (voting-data (unwrap! (map-get? film-voting-power { film-id: film-id }) ERR_NOT_FOUND))
      (existing-vote (map-get? backer-votes { film-id: film-id, voter: tx-sender }))
    )
    (asserts! (get is-funded film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (<= stacks-block-height (get voting-deadline voting-data)) ERR_DEADLINE_PASSED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    
    (let 
      (
        (vote-weight (get amount backing-data))
      )
      (map-set backer-votes
        { film-id: film-id, voter: tx-sender }
        { vote-weight: vote-weight, timestamp: stacks-block-height }
      )
      
      (map-set film-voting-power
        { film-id: film-id }
        (merge voting-data { total-votes: (+ (get total-votes voting-data) vote-weight) })
      )
      
      (ok vote-weight)
    )
  )
)

(define-public (distribute-rewards (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (voting-data (unwrap! (map-get? film-voting-power { film-id: film-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (get is-funded film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (> stacks-block-height (get voting-deadline voting-data)) ERR_DEADLINE_PASSED)
    (asserts! (not (get reward-distribution film-data)) ERR_ALREADY_EXISTS)
    
    (map-set films
      { film-id: film-id }
      (merge film-data { reward-distribution: true })
    )
    
    (ok true)
  )
)

(define-public (claim-premiere-invite (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: film-id, backer: tx-sender }) ERR_UNAUTHORIZED))
      (reward-id (var-get next-reward-id))
    )
    (asserts! (get reward-distribution film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (>= (get reward-tier backing-data) u2) ERR_UNAUTHORIZED)
    
    (map-set reward-claims
      { reward-id: reward-id }
      {
        film-id: film-id,
        recipient: tx-sender,
        reward-type: "premiere-invite",
        claimed: true,
        metadata: (get title film-data)
      }
    )
    
    (var-set next-reward-id (+ reward-id u1))
    (ok reward-id)
  )
)

(define-public (claim-streaming-rights (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: film-id, backer: tx-sender }) ERR_UNAUTHORIZED))
      (reward-id (var-get next-reward-id))
    )
    (asserts! (get reward-distribution film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (>= (get reward-tier backing-data) u1) ERR_UNAUTHORIZED)
    
    (map-set reward-claims
      { reward-id: reward-id }
      {
        film-id: film-id,
        recipient: tx-sender,
        reward-type: "streaming-rights",
        claimed: true,
        metadata: (get title film-data)
      }
    )
    
    (var-set next-reward-id (+ reward-id u1))
    (ok reward-id)
  )
)

(define-public (claim-nft-credits (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: film-id, backer: tx-sender }) ERR_UNAUTHORIZED))
      (reward-id (var-get next-reward-id))
    )
    (asserts! (get reward-distribution film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (>= (get reward-tier backing-data) u3) ERR_UNAUTHORIZED)
    
    (map-set reward-claims
      { reward-id: reward-id }
      {
        film-id: film-id,
        recipient: tx-sender,
        reward-type: "nft-credits",
        claimed: true,
        metadata: (get title film-data)
      }
    )
    
    (var-set next-reward-id (+ reward-id u1))
    (ok reward-id)
  )
)

(define-public (withdraw-funds (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (get is-funded film-data) ERR_FUNDING_NOT_COMPLETE)
    
    (try! (as-contract (stx-transfer? (get funding-raised film-data) tx-sender (get creator film-data))))
    (ok true)
  )
)

(define-read-only (get-film-details (film-id uint))
  (map-get? films { film-id: film-id })
)

(define-read-only (get-backer-info (film-id uint) (backer principal))
  (map-get? film-backers { film-id: film-id, backer: backer })
)

(define-read-only (get-voting-info (film-id uint))
  (map-get? film-voting-power { film-id: film-id })
)

(define-read-only (get-reward-claim (reward-id uint))
  (map-get? reward-claims { reward-id: reward-id })
)

(define-read-only (get-next-film-id)
  (var-get next-film-id)
)

(define-read-only (get-vote-info (film-id uint) (voter principal))
  (map-get? backer-votes { film-id: film-id, voter: voter })
)

(define-private (calculate-reward-tier (amount uint))
  (if (>= amount u1000000)
    u3
    (if (>= amount u500000)
      u2
      u1)
  )
)

(define-read-only (get-current-block-height)
  stacks-block-height
)

(define-read-only (is-film-deadline-passed (film-id uint))
  (match (map-get? films { film-id: film-id })
    film-data (> stacks-block-height (get deadline film-data))
    false
  )
)

(define-read-only (get-funding-progress (film-id uint))
  (match (map-get? films { film-id: film-id })
    film-data 
      (let 
        (
          (goal (get funding-goal film-data))
          (raised (get funding-raised film-data))
        )
        (some {
          funding-goal: goal,
          funding-raised: raised,
          percentage: (if (> goal u0) (/ (* raised u100) goal) u0),
          is-funded: (get is-funded film-data)
        })
      )
    none
  )
)
