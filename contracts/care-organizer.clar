;; care-organizer
;; Manages comprehensive care plans, medication tracking, appointments, and family coordination

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u500))
(define-constant err-not-found (err u501))
(define-constant err-unauthorized (err u502))
(define-constant err-invalid-data (err u503))
(define-constant err-already-exists (err u504))

;; Data Variables
(define-data-var care-plan-nonce uint u0)
(define-data-var medication-nonce uint u0)
(define-data-var appointment-nonce uint u0)
(define-data-var task-nonce uint u0)
(define-data-var document-nonce uint u0)
(define-data-var emergency-contact-nonce uint u0)
(define-data-var transition-nonce uint u0)

;; Care plan status
(define-constant plan-active u0)
(define-constant plan-paused u1)
(define-constant plan-archived u2)

;; Medication frequency
(define-constant freq-daily u0)
(define-constant freq-twice-daily u1)
(define-constant freq-weekly u2)
(define-constant freq-as-needed u3)

;; Task status
(define-constant task-pending u0)
(define-constant task-in-progress u1)
(define-constant task-completed u2)

;; Care location
(define-constant location-home u0)
(define-constant location-hospital u1)
(define-constant location-facility u2)
(define-constant location-rehab u3)

;; Data Maps
(define-map care-plans
    { plan-id: uint }
    {
        elder: principal,
        primary-caregiver: principal,
        medical-conditions: (string-ascii 500),
        dietary-restrictions: (string-ascii 300),
        mobility-level: uint,
        cognitive-status: (string-ascii 200),
        status: uint,
        created-at: uint,
        last-updated: uint
    }
)

(define-map medications
    { medication-id: uint }
    {
        plan-id: uint,
        medication-name: (string-ascii 100),
        dosage: (string-ascii 50),
        frequency: uint,
        prescribing-doctor: (string-ascii 100),
        pharmacy: (string-ascii 100),
        refill-date: uint,
        interactions-warning: (optional (string-ascii 300)),
        added-at: uint
    }
)

(define-map appointments
    { appointment-id: uint }
    {
        plan-id: uint,
        provider-name: (string-ascii 100),
        specialty: (string-ascii 100),
        appointment-date: uint,
        location: (string-ascii 200),
        transportation-arranged: bool,
        attending-family: (optional principal),
        notes: (optional (string-ascii 500)),
        completed: bool
    }
)

(define-map family-tasks
    { task-id: uint }
    {
        plan-id: uint,
        assigned-to: principal,
        task-description: (string-ascii 300),
        priority: uint,
        due-date: uint,
        status: uint,
        completed-at: (optional uint)
    }
)

(define-map documents
    { document-id: uint }
    {
        plan-id: uint,
        document-type: (string-ascii 100),
        document-hash: (string-ascii 64),
        uploaded-by: principal,
        accessible-to: (list 10 principal),
        uploaded-at: uint
    }
)

(define-map emergency-contacts
    { contact-id: uint }
    {
        plan-id: uint,
        contact-name: (string-ascii 100),
        relationship: (string-ascii 50),
        phone: (string-ascii 20),
        priority: uint
    }
)

(define-map care-transitions
    { transition-id: uint }
    {
        plan-id: uint,
        from-location: uint,
        to-location: uint,
        transition-date: uint,
        reason: (string-ascii 300),
        coordinated-by: principal
    }
)

(define-map family-members
    { plan-id: uint, member: principal }
    {
        role: (string-ascii 50),
        access-level: uint,
        added-at: uint
    }
)

(define-map medication-adherence
    { plan-id: uint, date: uint }
    {
        doses-taken: uint,
        doses-missed: uint,
        adherence-rate: uint
    }
)

;; Read-only functions
(define-read-only (get-care-plan (plan-id uint))
    (map-get? care-plans { plan-id: plan-id })
)

(define-read-only (get-medication (medication-id uint))
    (map-get? medications { medication-id: medication-id })
)

(define-read-only (get-appointment (appointment-id uint))
    (map-get? appointments { appointment-id: appointment-id })
)

(define-read-only (get-task (task-id uint))
    (map-get? family-tasks { task-id: task-id })
)

(define-read-only (get-document (document-id uint))
    (map-get? documents { document-id: document-id })
)

(define-read-only (get-emergency-contact (contact-id uint))
    (map-get? emergency-contacts { contact-id: contact-id })
)

(define-read-only (get-transition (transition-id uint))
    (map-get? care-transitions { transition-id: transition-id })
)

(define-read-only (is-family-member (plan-id uint) (member principal))
    (is-some (map-get? family-members { plan-id: plan-id, member: member }))
)

(define-read-only (get-adherence (plan-id uint) (date uint))
    (map-get? medication-adherence { plan-id: plan-id, date: date })
)

;; Public functions

;; Create care plan
(define-public (create-care-plan 
    (elder principal)
    (medical-conditions (string-ascii 500))
    (dietary-restrictions (string-ascii 300))
    (mobility-level uint)
    (cognitive-status (string-ascii 200)))
    (let
        (
            (plan-id (var-get care-plan-nonce))
        )
        (map-set care-plans
            { plan-id: plan-id }
            {
                elder: elder,
                primary-caregiver: tx-sender,
                medical-conditions: medical-conditions,
                dietary-restrictions: dietary-restrictions,
                mobility-level: mobility-level,
                cognitive-status: cognitive-status,
                status: plan-active,
                created-at: stacks-block-height,
                last-updated: stacks-block-height
            }
        )
        
        ;; Add creator as family member
        (map-set family-members
            { plan-id: plan-id, member: tx-sender }
            { role: "Primary Caregiver", access-level: u3, added-at: stacks-block-height }
        )
        
        (var-set care-plan-nonce (+ plan-id u1))
        (ok plan-id)
    )
)

;; Add family member
(define-public (add-family-member (plan-id uint) (member principal) (role (string-ascii 50)) (access-level uint))
    (let
        (
            (plan (unwrap! (get-care-plan plan-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get primary-caregiver plan)) err-unauthorized)
        (asserts! (<= access-level u3) err-invalid-data)
        
        (map-set family-members
            { plan-id: plan-id, member: member }
            { role: role, access-level: access-level, added-at: stacks-block-height }
        )
        (ok true)
    )
)

;; Add medication
(define-public (add-medication
    (plan-id uint)
    (medication-name (string-ascii 100))
    (dosage (string-ascii 50))
    (frequency uint)
    (prescribing-doctor (string-ascii 100))
    (pharmacy (string-ascii 100))
    (refill-date uint)
    (interactions-warning (optional (string-ascii 300))))
    (let
        (
            (medication-id (var-get medication-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set medications
            { medication-id: medication-id }
            {
                plan-id: plan-id,
                medication-name: medication-name,
                dosage: dosage,
                frequency: frequency,
                prescribing-doctor: prescribing-doctor,
                pharmacy: pharmacy,
                refill-date: refill-date,
                interactions-warning: interactions-warning,
                added-at: stacks-block-height
            }
        )
        (var-set medication-nonce (+ medication-id u1))
        (ok medication-id)
    )
)

;; Schedule appointment
(define-public (schedule-appointment
    (plan-id uint)
    (provider-name (string-ascii 100))
    (specialty (string-ascii 100))
    (appointment-date uint)
    (location (string-ascii 200))
    (attending-family (optional principal)))
    (let
        (
            (appointment-id (var-get appointment-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set appointments
            { appointment-id: appointment-id }
            {
                plan-id: plan-id,
                provider-name: provider-name,
                specialty: specialty,
                appointment-date: appointment-date,
                location: location,
                transportation-arranged: false,
                attending-family: attending-family,
                notes: none,
                completed: false
            }
        )
        (var-set appointment-nonce (+ appointment-id u1))
        (ok appointment-id)
    )
)

;; Complete appointment
(define-public (complete-appointment (appointment-id uint) (notes (string-ascii 500)))
    (let
        (
            (appointment (unwrap! (get-appointment appointment-id) err-not-found))
        )
        (asserts! (is-family-member (get plan-id appointment) tx-sender) err-unauthorized)
        
        (map-set appointments
            { appointment-id: appointment-id }
            (merge appointment {
                completed: true,
                notes: (some notes)
            })
        )
        (ok true)
    )
)

;; Assign task
(define-public (assign-task
    (plan-id uint)
    (assigned-to principal)
    (task-description (string-ascii 300))
    (priority uint)
    (due-date uint))
    (let
        (
            (task-id (var-get task-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        (asserts! (is-family-member plan-id assigned-to) err-unauthorized)
        (asserts! (<= priority u3) err-invalid-data)
        
        (map-set family-tasks
            { task-id: task-id }
            {
                plan-id: plan-id,
                assigned-to: assigned-to,
                task-description: task-description,
                priority: priority,
                due-date: due-date,
                status: task-pending,
                completed-at: none
            }
        )
        (var-set task-nonce (+ task-id u1))
        (ok task-id)
    )
)

;; Complete task
(define-public (complete-task (task-id uint))
    (let
        (
            (task (unwrap! (get-task task-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get assigned-to task)) err-unauthorized)
        
        (map-set family-tasks
            { task-id: task-id }
            (merge task {
                status: task-completed,
                completed-at: (some stacks-block-height)
            })
        )
        (ok true)
    )
)

;; Upload document
(define-public (upload-document
    (plan-id uint)
    (document-type (string-ascii 100))
    (document-hash (string-ascii 64))
    (accessible-to (list 10 principal)))
    (let
        (
            (document-id (var-get document-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set documents
            { document-id: document-id }
            {
                plan-id: plan-id,
                document-type: document-type,
                document-hash: document-hash,
                uploaded-by: tx-sender,
                accessible-to: accessible-to,
                uploaded-at: stacks-block-height
            }
        )
        (var-set document-nonce (+ document-id u1))
        (ok document-id)
    )
)

;; Add emergency contact
(define-public (add-emergency-contact
    (plan-id uint)
    (contact-name (string-ascii 100))
    (relationship (string-ascii 50))
    (phone (string-ascii 20))
    (priority uint))
    (let
        (
            (contact-id (var-get emergency-contact-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set emergency-contacts
            { contact-id: contact-id }
            {
                plan-id: plan-id,
                contact-name: contact-name,
                relationship: relationship,
                phone: phone,
                priority: priority
            }
        )
        (var-set emergency-contact-nonce (+ contact-id u1))
        (ok contact-id)
    )
)

;; Record care transition
(define-public (record-transition
    (plan-id uint)
    (from-location uint)
    (to-location uint)
    (reason (string-ascii 300)))
    (let
        (
            (transition-id (var-get transition-nonce))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set care-transitions
            { transition-id: transition-id }
            {
                plan-id: plan-id,
                from-location: from-location,
                to-location: to-location,
                transition-date: stacks-block-height,
                reason: reason,
                coordinated-by: tx-sender
            }
        )
        (var-set transition-nonce (+ transition-id u1))
        (ok transition-id)
    )
)

;; Record medication adherence
(define-public (record-adherence (plan-id uint) (date uint) (doses-taken uint) (doses-missed uint))
    (let
        (
            (total-doses (+ doses-taken doses-missed))
            (adherence-rate (if (> total-doses u0) (/ (* doses-taken u100) total-doses) u0))
        )
        (asserts! (is-family-member plan-id tx-sender) err-unauthorized)
        
        (map-set medication-adherence
            { plan-id: plan-id, date: date }
            {
                doses-taken: doses-taken,
                doses-missed: doses-missed,
                adherence-rate: adherence-rate
            }
        )
        (ok adherence-rate)
    )
)

;; Update care plan status
(define-public (update-plan-status (plan-id uint) (new-status uint))
    (let
        (
            (plan (unwrap! (get-care-plan plan-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get primary-caregiver plan)) err-unauthorized)
        
        (map-set care-plans
            { plan-id: plan-id }
            (merge plan {
                status: new-status,
                last-updated: stacks-block-height
            })
        )
        (ok true)
    )
)

