(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_DEADLINE_PASSED (err u104))
(define-constant ERR_FUNDING_NOT_COMPLETE (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_MILESTONE_NOT_READY (err u108))
(define-constant ERR_MILESTONE_COMPLETED (err u109))
(define-constant ERR_INSUFFICIENT_APPROVAL (err u110))
(define-constant ERR_REVENUE_NOT_DISTRIBUTED (err u111))
(define-constant ERR_NO_REVENUE_TO_CLAIM (err u112))
(define-constant ERR_ROYALTIES_ALREADY_CLAIMED (err u113))

(define-data-var next-film-id uint u0)
(define-data-var next-reward-id uint u0)
(define-data-var next-milestone-id uint u0)
(define-data-var creator-royalty-percentage uint u3000)
(define-data-var backers-royalty-percentage uint u7000)

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

(define-map milestones
  { milestone-id: uint }
  {
    film-id: uint,
    title: (string-ascii 64),
    funding-amount: uint,
    approval-votes: uint,
    rejection-votes: uint,
    voting-deadline: uint,
    is-completed: bool,
    funds-released: bool
  }
)

(define-map milestone-votes
  { milestone-id: uint, voter: principal }
  { vote-type: bool, vote-weight: uint }
)

(define-map film-revenue
  { film-id: uint }
  {
    total-revenue: uint,
    creator-share: uint,
    backers-share: uint,
    last-distribution-height: uint,
    is-distributing: bool
  }
)

(define-map backer-royalties
  { film-id: uint, backer: principal }
  {
    total-earned: uint,
    claimed-amount: uint,
    last-claim-height: uint
  }
)

(define-map revenue-distribution-log
  { film-id: uint, distribution-id: uint }
  {
    total-distributed: uint,
    creator-payout: uint,
    backers-payout: uint,
    distribution-height: uint
  }
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
    
    (map-set film-revenue 
      { film-id: film-id }
      {
        total-revenue: u0,
        creator-share: u0,
        backers-share: u0,
        last-distribution-height: u0,
        is-distributing: false
      }
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

(define-public (create-milestone (film-id uint) (title (string-ascii 64)) (funding-amount uint) (voting-days uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (milestone-id (var-get next-milestone-id))
      (voting-deadline (+ stacks-block-height (* voting-days u144)))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (get is-funded film-data) ERR_FUNDING_NOT_COMPLETE)
    (asserts! (> funding-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> voting-days u0) ERR_INVALID_AMOUNT)
    (asserts! (<= funding-amount (get funding-raised film-data)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set milestones
      { milestone-id: milestone-id }
      {
        film-id: film-id,
        title: title,
        funding-amount: funding-amount,
        approval-votes: u0,
        rejection-votes: u0,
        voting-deadline: voting-deadline,
        is-completed: false,
        funds-released: false
      }
    )
    
    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)
  )
)

(define-public (vote-on-milestone (milestone-id uint) (approve bool))
  (let 
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
      (film-data (unwrap! (map-get? films { film-id: (get film-id milestone-data) }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: (get film-id milestone-data), backer: tx-sender }) ERR_UNAUTHORIZED))
      (existing-vote (map-get? milestone-votes { milestone-id: milestone-id, voter: tx-sender }))
    )
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get voting-deadline milestone-data)) ERR_DEADLINE_PASSED)
    (asserts! (not (get is-completed milestone-data)) ERR_MILESTONE_COMPLETED)
    
    (let 
      (
        (vote-weight (get amount backing-data))
        (new-approval-votes (if approve (+ (get approval-votes milestone-data) vote-weight) (get approval-votes milestone-data)))
        (new-rejection-votes (if approve (get rejection-votes milestone-data) (+ (get rejection-votes milestone-data) vote-weight)))
      )
      (map-set milestone-votes
        { milestone-id: milestone-id, voter: tx-sender }
        { vote-type: approve, vote-weight: vote-weight }
      )
      
      (map-set milestones
        { milestone-id: milestone-id }
        (merge milestone-data {
          approval-votes: new-approval-votes,
          rejection-votes: new-rejection-votes
        })
      )
      
      (ok vote-weight)
    )
  )
)

(define-public (complete-milestone (milestone-id uint))
  (let 
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
      (film-data (unwrap! (map-get? films { film-id: (get film-id milestone-data) }) ERR_NOT_FOUND))
      (total-funding (get funding-raised film-data))
      (approval-threshold (/ (* total-funding u51) u100))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (> stacks-block-height (get voting-deadline milestone-data)) ERR_MILESTONE_NOT_READY)
    (asserts! (not (get is-completed milestone-data)) ERR_MILESTONE_COMPLETED)
    (asserts! (>= (get approval-votes milestone-data) approval-threshold) ERR_INSUFFICIENT_APPROVAL)
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { is-completed: true })
    )
    
    (ok true)
  )
)

(define-public (release-milestone-funds (milestone-id uint))
  (let 
    (
      (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
      (film-data (unwrap! (map-get? films { film-id: (get film-id milestone-data) }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (get is-completed milestone-data) ERR_MILESTONE_NOT_READY)
    (asserts! (not (get funds-released milestone-data)) ERR_ALREADY_EXISTS)
    
    (try! (as-contract (stx-transfer? (get funding-amount milestone-data) tx-sender (get creator film-data))))
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data { funds-released: true })
    )
    
    (ok true)
  )
)

(define-read-only (get-milestone-details (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-milestone-vote (milestone-id uint) (voter principal))
  (map-get? milestone-votes { milestone-id: milestone-id, voter: voter })
)

(define-read-only (get-next-milestone-id)
  (var-get next-milestone-id)
)

(define-public (deposit-revenue (film-id uint) (amount uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (revenue-data (unwrap! (map-get? film-revenue { film-id: film-id }) ERR_NOT_FOUND))
      (creator-share (/ (* amount (var-get creator-royalty-percentage)) u10000))
      (backers-share (- amount creator-share))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set film-revenue 
      { film-id: film-id }
      (merge revenue-data {
        total-revenue: (+ (get total-revenue revenue-data) amount),
        creator-share: (+ (get creator-share revenue-data) creator-share),
        backers-share: (+ (get backers-share revenue-data) backers-share)
      }))
    
    (ok true)
  )
)

(define-public (distribute-revenue (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (revenue-data (unwrap! (map-get? film-revenue { film-id: film-id }) ERR_NOT_FOUND))
      (distribution-id (var-get next-reward-id))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (> (get total-revenue revenue-data) u0) ERR_NO_REVENUE_TO_CLAIM)
    (asserts! (not (get is-distributing revenue-data)) ERR_ALREADY_EXISTS)
    
    (map-set film-revenue 
      { film-id: film-id }
      (merge revenue-data { is-distributing: true, last-distribution-height: stacks-block-height }))
    
    (map-set revenue-distribution-log 
      { film-id: film-id, distribution-id: distribution-id }
      {
        total-distributed: (get total-revenue revenue-data),
        creator-payout: (get creator-share revenue-data),
        backers-payout: (get backers-share revenue-data),
        distribution-height: stacks-block-height
      })
    
    (var-set next-reward-id (+ distribution-id u1))
    (ok distribution-id)
  )
)

(define-public (claim-creator-royalties (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (revenue-data (unwrap! (map-get? film-revenue { film-id: film-id }) ERR_NOT_FOUND))
      (creator-share (get creator-share revenue-data))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (get is-distributing revenue-data) ERR_REVENUE_NOT_DISTRIBUTED)
    (asserts! (> creator-share u0) ERR_NO_REVENUE_TO_CLAIM)
    
    (try! (as-contract (stx-transfer? creator-share tx-sender (get creator film-data))))
    
    (map-set film-revenue 
      { film-id: film-id }
      (merge revenue-data { creator-share: u0 }))
      
    (ok creator-share)
  )
)

(define-public (claim-backer-royalties (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (revenue-data (unwrap! (map-get? film-revenue { film-id: film-id }) ERR_NOT_FOUND))
      (backing-data (unwrap! (map-get? film-backers { film-id: film-id, backer: tx-sender }) ERR_UNAUTHORIZED))
      (backer-royalty (unwrap! (map-get? backer-royalties { film-id: film-id, backer: tx-sender }) ERR_NOT_FOUND))
      (backers-share (get backers-share revenue-data))
      (total-funding (get funding-raised film-data))
      (backer-contribution (get amount backing-data))
      (claimable-amount (/ (* backers-share backer-contribution) total-funding))
    )
    (asserts! (get is-distributing revenue-data) ERR_REVENUE_NOT_DISTRIBUTED)
    (asserts! (> claimable-amount u0) ERR_NO_REVENUE_TO_CLAIM)
    (asserts! (is-eq (get last-claim-height backer-royalty) u0) ERR_ROYALTIES_ALREADY_CLAIMED)
    
    (try! (as-contract (stx-transfer? claimable-amount tx-sender tx-sender)))
    
    (map-set backer-royalties 
      { film-id: film-id, backer: tx-sender }
      (merge backer-royalty {
        total-earned: (+ (get total-earned backer-royalty) claimable-amount),
        claimed-amount: (+ (get claimed-amount backer-royalty) claimable-amount),
        last-claim-height: stacks-block-height
      }))
    
    (ok claimable-amount)
  )
)

(define-public (reset-distribution (film-id uint))
  (let 
    (
      (film-data (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND))
      (revenue-data (unwrap! (map-get? film-revenue { film-id: film-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator film-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get creator-share revenue-data) u0) ERR_NO_REVENUE_TO_CLAIM)
    
    (map-set film-revenue 
      { film-id: film-id }
      (merge revenue-data { is-distributing: false, backers-share: u0, total-revenue: u0 }))
    
    (ok true)
  )
)

(define-read-only (get-film-revenue (film-id uint))
  (map-get? film-revenue { film-id: film-id })
)

(define-read-only (get-backer-royalties (film-id uint) (backer principal))
  (map-get? backer-royalties { film-id: film-id, backer: backer })
)

(define-read-only (get-claimable-royalties (film-id uint) (backer principal))
  (match (map-get? film-revenue { film-id: film-id })
    revenue-data 
      (match (map-get? film-backers { film-id: film-id, backer: backer })
        backing-data
          (let 
            (
              (backers-share (get backers-share revenue-data))
              (total-funding (get funding-raised (unwrap! (map-get? films { film-id: film-id }) ERR_NOT_FOUND)))
              (backer-contribution (get amount backing-data))
            )
            (ok (some (/ (* backers-share backer-contribution) total-funding))))
        (ok none))
    (ok none))
)

(define-read-only (get-revenue-distribution-log (film-id uint) (distribution-id uint))
  (map-get? revenue-distribution-log { film-id: film-id, distribution-id: distribution-id })
)

(define-read-only (get-royalty-percentages)
  {
    creator: (var-get creator-royalty-percentage),
    backers: (var-get backers-royalty-percentage)
  }
)
