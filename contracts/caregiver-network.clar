;; caregiver-network
;; Professional caregiver marketplace with scheduling, payments, and quality monitoring

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u600))
(define-constant err-not-found (err u601))
(define-constant err-unauthorized (err u602))
(define-constant err-invalid-data (err u603))
(define-constant err-already-exists (err u604))
(define-constant err-insufficient-payment (err u605))

;; Data Variables
(define-data-var caregiver-nonce uint u0)
(define-data-var shift-nonce uint u0)
(define-data-var payment-nonce uint u0)
(define-data-var review-nonce uint u0)
(define-data-var training-nonce uint u0)

;; Caregiver status
(define-constant status-pending u0)
(define-constant status-verified u1)
(define-constant status-active u2)
(define-constant status-suspended u3)

;; Shift status
(define-constant shift-scheduled u0)
(define-constant shift-in-progress u1)
(define-constant shift-completed u2)
(define-constant shift-cancelled u3)

;; Care type
(define-constant care-companion u0)
(define-constant care-medical u1)
(define-constant care-specialized u2)
(define-constant care-respite u3)

;; Data Maps
(define-map caregivers
    { caregiver-id: uint }
    {
        caregiver: principal,
        name: (string-ascii 100),
        certification: (string-ascii 100),
        specializations: (string-ascii 300),
        years-experience: uint,
        hourly-rate: uint,
        status: uint,
        background-check: bool,
        rating: uint,
        total-reviews: uint,
        joined-at: uint
    }
)

(define-map caregiver-availability
    { caregiver-id: uint, date: uint }
    {
        available-hours: (list 24 bool),
        max-hours: uint
    }
)

(define-map shifts
    { shift-id: uint }
    {
        caregiver-id: uint,
        family: principal,
        care-plan-id: uint,
        care-type: uint,
        start-time: uint,
        end-time: uint,
        hourly-rate: uint,
        status: uint,
        notes: (optional (string-ascii 500))
    }
)

(define-map shift-payments
    { payment-id: uint }
    {
        shift-id: uint,
        amount: uint,
        paid-by: principal,
        paid-to: principal,
        paid-at: uint,
        released: bool
    }
)

(define-map caregiver-reviews
    { review-id: uint }
    {
        caregiver-id: uint,
        reviewer: principal,
        shift-id: uint,
        rating: uint,
        comment: (string-ascii 500),
        reviewed-at: uint
    }
)

(define-map training-resources
    { training-id: uint }
    {
        title: (string-ascii 200),
        description: (string-ascii 500),
        resource-hash: (string-ascii 64),
        required-for: (string-ascii 100),
        created-at: uint
    }
)

(define-map caregiver-training
    { caregiver-id: uint, training-id: uint }
    {
        completed: bool,
        completed-at: (optional uint),
        score: (optional uint)
    }
)

(define-map care-team-members
    { care-plan-id: uint, caregiver-id: uint }
    {
        role: (string-ascii 100),
        primary: bool,
        active: bool,
        added-at: uint
    }
)

(define-map caregiver-by-principal
    { caregiver: principal }
    { caregiver-id: uint }
)

;; Read-only functions
(define-read-only (get-caregiver (caregiver-id uint))
    (map-get? caregivers { caregiver-id: caregiver-id })
)

(define-read-only (get-caregiver-by-principal (caregiver principal))
    (match (map-get? caregiver-by-principal { caregiver: caregiver })
        mapping (get-caregiver (get caregiver-id mapping))
        none
    )
)

(define-read-only (get-shift (shift-id uint))
    (map-get? shifts { shift-id: shift-id })
)

(define-read-only (get-payment (payment-id uint))
    (map-get? shift-payments { payment-id: payment-id })
)

(define-read-only (get-review (review-id uint))
    (map-get? caregiver-reviews { review-id: review-id })
)

(define-read-only (get-training (training-id uint))
    (map-get? training-resources { training-id: training-id })
)

(define-read-only (is-trained (caregiver-id uint) (training-id uint))
    (match (map-get? caregiver-training { caregiver-id: caregiver-id, training-id: training-id })
        training (get completed training)
        false
    )
)

;; Public functions

;; Register as caregiver
(define-public (register-caregiver
    (name (string-ascii 100))
    (certification (string-ascii 100))
    (specializations (string-ascii 300))
    (years-experience uint)
    (hourly-rate uint))
    (let
        (
            (caregiver-id (var-get caregiver-nonce))
        )
        (asserts! (is-none (map-get? caregiver-by-principal { caregiver: tx-sender })) err-already-exists)
        
        (map-set caregivers
            { caregiver-id: caregiver-id }
            {
                caregiver: tx-sender,
                name: name,
                certification: certification,
                specializations: specializations,
                years-experience: years-experience,
                hourly-rate: hourly-rate,
                status: status-pending,
                background-check: false,
                rating: u0,
                total-reviews: u0,
                joined-at: stacks-block-height
            }
        )
        
        (map-set caregiver-by-principal
            { caregiver: tx-sender }
            { caregiver-id: caregiver-id }
        )
        
        (var-set caregiver-nonce (+ caregiver-id u1))
        (ok caregiver-id)
    )
)

;; Verify caregiver
(define-public (verify-caregiver (caregiver-id uint) (background-check-passed bool))
    (let
        (
            (caregiver (unwrap! (get-caregiver caregiver-id) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set caregivers
            { caregiver-id: caregiver-id }
            (merge caregiver {
                status: (if background-check-passed status-verified status-suspended),
                background-check: background-check-passed
            })
        )
        (ok true)
    )
)

;; Activate caregiver
(define-public (activate-caregiver (caregiver-id uint))
    (let
        (
            (caregiver (unwrap! (get-caregiver caregiver-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get caregiver caregiver)) err-unauthorized)
        (asserts! (is-eq (get status caregiver) status-verified) err-invalid-data)
        
        (map-set caregivers
            { caregiver-id: caregiver-id }
            (merge caregiver { status: status-active })
        )
        (ok true)
    )
)

;; Schedule shift
(define-public (schedule-shift
    (caregiver-id uint)
    (care-plan-id uint)
    (care-type uint)
    (start-time uint)
    (end-time uint))
    (let
        (
            (shift-id (var-get shift-nonce))
            (caregiver (unwrap! (get-caregiver caregiver-id) err-not-found))
        )
        (asserts! (is-eq (get status caregiver) status-active) err-unauthorized)
        (asserts! (> end-time start-time) err-invalid-data)
        
        (map-set shifts
            { shift-id: shift-id }
            {
                caregiver-id: caregiver-id,
                family: tx-sender,
                care-plan-id: care-plan-id,
                care-type: care-type,
                start-time: start-time,
                end-time: end-time,
                hourly-rate: (get hourly-rate caregiver),
                status: shift-scheduled,
                notes: none
            }
        )
        (var-set shift-nonce (+ shift-id u1))
        (ok shift-id)
    )
)

;; Start shift
(define-public (start-shift (shift-id uint))
    (let
        (
            (shift (unwrap! (get-shift shift-id) err-not-found))
            (caregiver (unwrap! (get-caregiver (get caregiver-id shift)) err-not-found))
        )
        (asserts! (is-eq tx-sender (get caregiver caregiver)) err-unauthorized)
        (asserts! (is-eq (get status shift) shift-scheduled) err-invalid-data)
        
        (map-set shifts
            { shift-id: shift-id }
            (merge shift { status: shift-in-progress })
        )
        (ok true)
    )
)

;; Complete shift
(define-public (complete-shift (shift-id uint) (notes (string-ascii 500)))
    (let
        (
            (shift (unwrap! (get-shift shift-id) err-not-found))
            (caregiver (unwrap! (get-caregiver (get caregiver-id shift)) err-not-found))
        )
        (asserts! (is-eq tx-sender (get caregiver caregiver)) err-unauthorized)
        (asserts! (is-eq (get status shift) shift-in-progress) err-invalid-data)
        
        (map-set shifts
            { shift-id: shift-id }
            (merge shift {
                status: shift-completed,
                notes: (some notes)
            })
        )
        (ok true)
    )
)

;; Process payment
(define-public (process-payment (shift-id uint) (amount uint))
    (let
        (
            (shift (unwrap! (get-shift shift-id) err-not-found))
            (caregiver (unwrap! (get-caregiver (get caregiver-id shift)) err-not-found))
            (payment-id (var-get payment-nonce))
            (hours (- (get end-time shift) (get start-time shift)))
            (expected-amount (* hours (get hourly-rate shift)))
        )
        (asserts! (is-eq tx-sender (get family shift)) err-unauthorized)
        (asserts! (is-eq (get status shift) shift-completed) err-invalid-data)
        (asserts! (>= amount expected-amount) err-insufficient-payment)
        
        ;; Transfer STX to escrow (contract)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set shift-payments
            { payment-id: payment-id }
            {
                shift-id: shift-id,
                amount: amount,
                paid-by: tx-sender,
                paid-to: (get caregiver caregiver),
                paid-at: stacks-block-height,
                released: false
            }
        )
        (var-set payment-nonce (+ payment-id u1))
        (ok payment-id)
    )
)

;; Release payment
(define-public (release-payment (payment-id uint))
    (let
        (
            (payment (unwrap! (get-payment payment-id) err-not-found))
        )
        (asserts! (or (is-eq tx-sender (get paid-by payment)) (is-eq tx-sender contract-owner)) err-unauthorized)
        (asserts! (not (get released payment)) err-already-exists)
        
        ;; Transfer from escrow to caregiver
        (try! (as-contract (stx-transfer? (get amount payment) tx-sender (get paid-to payment))))
        
        (map-set shift-payments
            { payment-id: payment-id }
            (merge payment { released: true })
        )
        (ok true)
    )
)

;; Submit review
(define-public (submit-review (caregiver-id uint) (shift-id uint) (rating uint) (comment (string-ascii 500)))
    (let
        (
            (review-id (var-get review-nonce))
            (caregiver (unwrap! (get-caregiver caregiver-id) err-not-found))
            (shift (unwrap! (get-shift shift-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get family shift)) err-unauthorized)
        (asserts! (is-eq (get status shift) shift-completed) err-invalid-data)
        (asserts! (<= rating u5) err-invalid-data)
        
        (map-set caregiver-reviews
            { review-id: review-id }
            {
                caregiver-id: caregiver-id,
                reviewer: tx-sender,
                shift-id: shift-id,
                rating: rating,
                comment: comment,
                reviewed-at: stacks-block-height
            }
        )
        
        ;; Update caregiver rating
        (let
            (
                (total-reviews (+ (get total-reviews caregiver) u1))
                (new-rating (/ (+ (* (get rating caregiver) (get total-reviews caregiver)) rating) total-reviews))
            )
            (map-set caregivers
                { caregiver-id: caregiver-id }
                (merge caregiver {
                    rating: new-rating,
                    total-reviews: total-reviews
                })
            )
        )
        
        (var-set review-nonce (+ review-id u1))
        (ok review-id)
    )
)

;; Add training resource
(define-public (add-training
    (title (string-ascii 200))
    (description (string-ascii 500))
    (resource-hash (string-ascii 64))
    (required-for (string-ascii 100)))
    (let
        (
            (training-id (var-get training-nonce))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set training-resources
            { training-id: training-id }
            {
                title: title,
                description: description,
                resource-hash: resource-hash,
                required-for: required-for,
                created-at: stacks-block-height
            }
        )
        (var-set training-nonce (+ training-id u1))
        (ok training-id)
    )
)

;; Complete training
(define-public (complete-training (caregiver-id uint) (training-id uint) (score uint))
    (let
        (
            (caregiver (unwrap! (get-caregiver caregiver-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get caregiver caregiver)) err-unauthorized)
        (asserts! (<= score u100) err-invalid-data)
        
        (map-set caregiver-training
            { caregiver-id: caregiver-id, training-id: training-id }
            {
                completed: true,
                completed-at: (some stacks-block-height),
                score: (some score)
            }
        )
        (ok true)
    )
)

;; Add to care team
(define-public (add-to-care-team (care-plan-id uint) (caregiver-id uint) (role (string-ascii 100)) (primary bool))
    (begin
        (asserts! (is-some (get-caregiver caregiver-id)) err-not-found)
        
        (map-set care-team-members
            { care-plan-id: care-plan-id, caregiver-id: caregiver-id }
            {
                role: role,
                primary: primary,
                active: true,
                added-at: stacks-block-height
            }
        )
        (ok true)
    )
)

