;; Creative Industries Cryptocurrency Contract
;; A comprehensive smart contract for managing creative works, NFTs, and royalty distribution

;; Contract constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_ROYALTY (err u105))

;; Data variables
(define-data-var next-work-id uint u1)
(define-data-var platform-fee uint u250) ;; 2.5% in basis points
(define-data-var block-counter uint u0) ;; Manual block counter for timestamps

;; Creative work structure
(define-map creative-works
  { work-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    price: uint,
    royalty-percentage: uint,
    total-supply: uint,
    available-supply: uint,
    created-at: uint,
    is-active: bool
  }
)
;; Ownership tracking
(define-map work-ownership
  { work-id: uint, owner: principal }
  { quantity: uint }
)

;; Royalty recipients for collaborative works
(define-map royalty-splits
  { work-id: uint, recipient: principal }
  { percentage: uint }
)

;; Marketplace listings
(define-map marketplace-listings
  { work-id: uint, seller: principal }
  {
    quantity: uint,
    price-per-unit: uint,
    listed-at: uint,
    is-active: bool
  }
)

;; Creator profiles
(define-map creator-profiles
  { creator: principal }
  {
    name: (string-ascii 100),
    bio: (string-ascii 500),
    portfolio-url: (string-ascii 200),
    total-works: uint,
    total-earnings: uint,
    verification-status: bool
  }
)

;; Events
(define-private (emit-work-created (work-id uint) (creator principal))
  (print { event: "work-created", work-id: work-id, creator: creator })
)

(define-private (emit-work-purchased (work-id uint) (buyer principal) (seller principal) (quantity uint) (total-price uint))
  (print { event: "work-purchased", work-id: work-id, buyer: buyer, seller: seller, quantity: quantity, total-price: total-price })
)

(define-private (emit-royalty-paid (work-id uint) (recipient principal) (amount uint))
  (print { event: "royalty-paid", work-id: work-id, recipient: recipient, amount: amount })
)

;; Helper functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee)) u10000)
)

(define-private (calculate-royalty (amount uint) (percentage uint))
  (/ (* amount percentage) u10000)
)

(define-private (get-current-timestamp)
  (begin
    (var-set block-counter (+ (var-get block-counter) u1))
    (var-get block-counter)
  )
)

;; Creator profile functions
(define-public (create-creator-profile (name (string-ascii 100)) (bio (string-ascii 500)) (portfolio-url (string-ascii 200)))
  (let ((existing-profile (map-get? creator-profiles { creator: tx-sender })))
    (if (is-some existing-profile)
      ERR_ALREADY_EXISTS
      (begin
        (map-set creator-profiles
          { creator: tx-sender }
          {
            name: name,
            bio: bio,
            portfolio-url: portfolio-url,
            total-works: u0,
            total-earnings: u0,
            verification-status: false
          }
        )
        (ok true)
      )
    )
  )
)

(define-public (update-creator-profile (name (string-ascii 100)) (bio (string-ascii 500)) (portfolio-url (string-ascii 200)))
  (let ((profile (unwrap! (map-get? creator-profiles { creator: tx-sender }) ERR_NOT_FOUND)))
    (map-set creator-profiles
      { creator: tx-sender }
      (merge profile {
        name: name,
        bio: bio,
        portfolio-url: portfolio-url
      })
    )
    (ok true)
  )
)

;; Creative work functions
(define-public (create-creative-work 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (category (string-ascii 50))
  (price uint)
  (royalty-percentage uint)
  (total-supply uint)
)
  (let ((work-id (var-get next-work-id)))
    (if (or (> royalty-percentage u5000) (is-eq total-supply u0) (is-eq price u0))
      ERR_INVALID_AMOUNT
      (begin
        ;; Create the work
        (map-set creative-works
          { work-id: work-id }
          {
            creator: tx-sender,
            title: title,
            description: description,
            category: category,
            price: price,
            royalty-percentage: royalty-percentage,
            total-supply: total-supply,
            available-supply: total-supply,
            created-at: (get-current-timestamp),
            is-active: true
          }
        )
        
        ;; Set creator as initial owner
        (map-set work-ownership
          { work-id: work-id, owner: tx-sender }
          { quantity: total-supply }
        )
        
        ;; Update creator profile
        (match (map-get? creator-profiles { creator: tx-sender })
          profile (map-set creator-profiles
            { creator: tx-sender }
            (merge profile { total-works: (+ (get total-works profile) u1) })
          )
          false ;; Profile doesn't exist, that's okay
        )
        
        ;; Increment work ID counter
        (var-set next-work-id (+ work-id u1))
        
        ;; Emit event
        (emit-work-created work-id tx-sender)
        
        (ok work-id)
      )
    )
  )
)

;; Add royalty split for collaborative works
(define-public (add-royalty-split (work-id uint) (recipient principal) (percentage uint))
  (let ((work (unwrap! (map-get? creative-works { work-id: work-id }) ERR_NOT_FOUND)))
    (if (and (is-eq tx-sender (get creator work)) (<= percentage u10000))
      (begin
        (map-set royalty-splits
          { work-id: work-id, recipient: recipient }
          { percentage: percentage }
        )
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Marketplace functions
(define-public (list-work-for-sale (work-id uint) (quantity uint) (price-per-unit uint))
  (let (
    (work (unwrap! (map-get? creative-works { work-id: work-id }) ERR_NOT_FOUND))
    (ownership (unwrap! (map-get? work-ownership { work-id: work-id, owner: tx-sender }) ERR_NOT_FOUND))
  )
    (if (and (>= (get quantity ownership) quantity) (> price-per-unit u0) (> quantity u0))
      (begin
        (map-set marketplace-listings
          { work-id: work-id, seller: tx-sender }
          {
            quantity: quantity,
            price-per-unit: price-per-unit,
            listed-at: (get-current-timestamp),
            is-active: true
          }
        )
        (ok true)
      )
      ERR_INVALID_AMOUNT
    )
  )
)

(define-public (cancel-listing (work-id uint))
  (let ((listing (unwrap! (map-get? marketplace-listings { work-id: work-id, seller: tx-sender }) ERR_NOT_FOUND)))
    (map-set marketplace-listings
      { work-id: work-id, seller: tx-sender }
      (merge listing { is-active: false })
    )
    (ok true)
  )
)

(define-public (purchase-work (work-id uint) (seller principal) (quantity uint))
  (let (
    (work (unwrap! (map-get? creative-works { work-id: work-id }) ERR_NOT_FOUND))
    (listing (unwrap! (map-get? marketplace-listings { work-id: work-id, seller: seller }) ERR_NOT_FOUND))
    (seller-ownership (unwrap! (map-get? work-ownership { work-id: work-id, owner: seller }) ERR_NOT_FOUND))
    (buyer-ownership (default-to { quantity: u0 } (map-get? work-ownership { work-id: work-id, owner: tx-sender })))
    (total-price (* quantity (get price-per-unit listing)))
    (fee-amount (calculate-platform-fee total-price))
    (royalty-amount (calculate-royalty total-price (get royalty-percentage work)))
    (seller-amount (- (- total-price fee-amount) royalty-amount))
  )
    (if (and 
          (get is-active listing)
          (>= (get quantity listing) quantity)
          (>= (get quantity seller-ownership) quantity)
        )
      (begin
        ;; Transfer STX from buyer to seller
        (try! (stx-transfer? seller-amount tx-sender seller)) 
        ;; Pay platform fee
        (try! (stx-transfer? fee-amount tx-sender CONTRACT_OWNER))
        
        ;; Pay royalty to creator
        (try! (stx-transfer? royalty-amount tx-sender (get creator work)))
        
        ;; Update ownership records
        (map-set work-ownership
          { work-id: work-id, owner: seller }
          { quantity: (- (get quantity seller-ownership) quantity) }
        )
        
        (map-set work-ownership
          { work-id: work-id, owner: tx-sender }
          { quantity: (+ (get quantity buyer-ownership) quantity) }
        )
        
        ;; Update listing
        (if (is-eq (get quantity listing) quantity)
          (map-set marketplace-listings
            { work-id: work-id, seller: seller }
            (merge listing { is-active: false })
          )
          (map-set marketplace-listings
            { work-id: work-id, seller: seller }
            (merge listing { quantity: (- (get quantity listing) quantity) })
          )
        )  
        ;; Update creator earnings
        (match (map-get? creator-profiles { creator: (get creator work) })
          profile (map-set creator-profiles
            { creator: (get creator work) }
            (merge profile { total-earnings: (+ (get total-earnings profile) royalty-amount) })
          )
          false
        )
        
        ;; Emit events
        (emit-work-purchased work-id tx-sender seller quantity total-price)
        (emit-royalty-paid work-id (get creator work) royalty-amount)
        
        (ok true)
      )
      ERR_INVALID_AMOUNT
    )
  )
)

;; Read-only functions
(define-read-only (get-work-details (work-id uint))
  (map-get? creative-works { work-id: work-id })
)

(define-read-only (get-work-ownership (work-id uint) (owner principal))
  (map-get? work-ownership { work-id: work-id, owner: owner })
)

(define-read-only (get-creator-profile (creator principal))
  (map-get? creator-profiles { creator: creator })
)

(define-read-only (get-marketplace-listing (work-id uint) (seller principal))
  (map-get? marketplace-listings { work-id: work-id, seller: seller })
)

(define-read-only (get-royalty-split (work-id uint) (recipient principal))
  (map-get? royalty-splits { work-id: work-id, recipient: recipient })
)

(define-read-only (get-next-work-id)
  (var-get next-work-id)
)

(define-read-only (get-platform-fee)
  (var-get platform-fee)
)

;; Admin functions
(define-public (set-platform-fee (new-fee uint))
  (if (is-contract-owner)
    (begin
      (var-set platform-fee new-fee)
      (ok true)
    )
    ERR_UNAUTHORIZED
  )
)

(define-public (verify-creator (creator principal))
  (if (is-contract-owner)
    (let ((profile (unwrap! (map-get? creator-profiles { creator: creator }) ERR_NOT_FOUND)))
      (map-set creator-profiles
        { creator: creator }
        (merge profile { verification-status: true })
      )
      (ok true)
    )
    ERR_UNAUTHORIZED
  )
)

(define-public (deactivate-work (work-id uint))
  (let ((work (unwrap! (map-get? creative-works { work-id: work-id }) ERR_NOT_FOUND)))
    (if (or (is-contract-owner) (is-eq tx-sender (get creator work)))
      (begin
        (map-set creative-works
          { work-id: work-id }
          (merge work { is-active: false })
        )
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)