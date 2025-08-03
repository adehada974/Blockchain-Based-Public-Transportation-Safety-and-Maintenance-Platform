;; Accident Investigation Coordination Contract
;; Manages investigation of transit accidents and implements safety improvements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVESTIGATION-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-INVALID-STATUS (err u303))
(define-constant ERR-EVIDENCE-NOT-FOUND (err u304))
(define-constant ERR-RECOMMENDATION-NOT-FOUND (err u305))

;; Data Variables
(define-data-var next-investigation-id uint u1)
(define-data-var next-evidence-id uint u1)
(define-data-var next-recommendation-id uint u1)

;; Data Maps
(define-map investigations
  { investigation-id: uint }
  {
    accident-date: uint,
    location: (string-ascii 100),
    severity: uint,
    description: (string-ascii 500),
    lead-investigator: principal,
    status: (string-ascii 20),
    start-date: uint,
    completion-date: (optional uint),
    final-report: (optional (string-ascii 1000))
  }
)

(define-map evidence-items
  { evidence-id: uint }
  {
    investigation-id: uint,
    evidence-type: (string-ascii 50),
    description: (string-ascii 300),
    collected-by: principal,
    collection-date: uint,
    chain-of-custody: (list 10 principal),
    status: (string-ascii 20)
  }
)

(define-map safety-recommendations
  { recommendation-id: uint }
  {
    investigation-id: uint,
    recommendation-type: (string-ascii 50),
    description: (string-ascii 500),
    priority: uint,
    assigned-to: (optional principal),
    implementation-date: (optional uint),
    status: (string-ascii 20),
    created-date: uint
  }
)

(define-map investigation-team
  { investigation-id: uint, investigator: principal }
  {
    role: (string-ascii 30),
    assigned-date: uint,
    status: (string-ascii 20)
  }
)

(define-map authorized-investigators principal bool)
(define-map safety-officers principal bool)

;; Authorization Functions
(define-public (add-authorized-investigator (investigator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-investigators investigator true))
  )
)

(define-public (add-safety-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set safety-officers officer true))
  )
)

;; Investigation Management Functions
(define-public (initiate-investigation
  (accident-date uint)
  (location (string-ascii 100))
  (severity uint)
  (description (string-ascii 500))
  (lead-investigator principal))
  (let ((investigation-id (var-get next-investigation-id)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? safety-officers tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (<= accident-date block-height) ERR-INVALID-INPUT)
      (asserts! (> (len location) u0) ERR-INVALID-INPUT)
      (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-INPUT)
      (asserts! (> (len description) u0) ERR-INVALID-INPUT)
      (asserts! (default-to false (map-get? authorized-investigators lead-investigator)) ERR-NOT-AUTHORIZED)

      (map-set investigations
        { investigation-id: investigation-id }
        {
          accident-date: accident-date,
          location: location,
          severity: severity,
          description: description,
          lead-investigator: lead-investigator,
          status: "initiated",
          start-date: block-height,
          completion-date: none,
          final-report: none
        }
      )

      (var-set next-investigation-id (+ investigation-id u1))
      (ok investigation-id)
    )
  )
)

(define-public (assign-investigator
  (investigation-id uint)
  (investigator principal)
  (role (string-ascii 30)))
  (let ((investigation (unwrap! (map-get? investigations { investigation-id: investigation-id }) ERR-INVESTIGATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (is-eq tx-sender (get lead-investigator investigation)))
                ERR-NOT-AUTHORIZED)
      (asserts! (default-to false (map-get? authorized-investigators investigator)) ERR-NOT-AUTHORIZED)
      (asserts! (> (len role) u0) ERR-INVALID-INPUT)

      (ok (map-set investigation-team
        { investigation-id: investigation-id, investigator: investigator }
        {
          role: role,
          assigned-date: block-height,
          status: "active"
        }
      ))
    )
  )
)

(define-public (update-investigation-status
  (investigation-id uint)
  (new-status (string-ascii 20)))
  (let ((investigation (unwrap! (map-get? investigations { investigation-id: investigation-id }) ERR-INVESTIGATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (is-eq tx-sender (get lead-investigator investigation)))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

      (ok (map-set investigations
        { investigation-id: investigation-id }
        (merge investigation { status: new-status })
      ))
    )
  )
)

;; Evidence Management Functions
(define-public (collect-evidence
  (investigation-id uint)
  (evidence-type (string-ascii 50))
  (description (string-ascii 300)))
  (let ((evidence-id (var-get next-evidence-id))
        (investigation (unwrap! (map-get? investigations { investigation-id: investigation-id }) ERR-INVESTIGATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender (get lead-investigator investigation))
                    (is-some (map-get? investigation-team { investigation-id: investigation-id, investigator: tx-sender })))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len evidence-type) u0) ERR-INVALID-INPUT)
      (asserts! (> (len description) u0) ERR-INVALID-INPUT)

      (map-set evidence-items
        { evidence-id: evidence-id }
        {
          investigation-id: investigation-id,
          evidence-type: evidence-type,
          description: description,
          collected-by: tx-sender,
          collection-date: block-height,
          chain-of-custody: (list tx-sender),
          status: "collected"
        }
      )

      (var-set next-evidence-id (+ evidence-id u1))
      (ok evidence-id)
    )
  )
)

(define-public (transfer-evidence
  (evidence-id uint)
  (new-custodian principal))
  (let ((evidence (unwrap! (map-get? evidence-items { evidence-id: evidence-id }) ERR-EVIDENCE-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? authorized-investigators tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (default-to false (map-get? authorized-investigators new-custodian)) ERR-NOT-AUTHORIZED)

      (let ((updated-chain (unwrap! (as-max-len? (append (get chain-of-custody evidence) new-custodian) u10) ERR-INVALID-INPUT)))
        (ok (map-set evidence-items
          { evidence-id: evidence-id }
          (merge evidence { chain-of-custody: updated-chain })
        ))
      )
    )
  )
)

;; Safety Recommendations Functions
(define-public (create-recommendation
  (investigation-id uint)
  (recommendation-type (string-ascii 50))
  (description (string-ascii 500))
  (priority uint))
  (let ((recommendation-id (var-get next-recommendation-id))
        (investigation (unwrap! (map-get? investigations { investigation-id: investigation-id }) ERR-INVESTIGATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender (get lead-investigator investigation))
                    (is-some (map-get? investigation-team { investigation-id: investigation-id, investigator: tx-sender })))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len recommendation-type) u0) ERR-INVALID-INPUT)
      (asserts! (> (len description) u0) ERR-INVALID-INPUT)
      (asserts! (and (>= priority u1) (<= priority u5)) ERR-INVALID-INPUT)

      (map-set safety-recommendations
        { recommendation-id: recommendation-id }
        {
          investigation-id: investigation-id,
          recommendation-type: recommendation-type,
          description: description,
          priority: priority,
          assigned-to: none,
          implementation-date: none,
          status: "pending",
          created-date: block-height
        }
      )

      (var-set next-recommendation-id (+ recommendation-id u1))
      (ok recommendation-id)
    )
  )
)

(define-public (assign-recommendation
  (recommendation-id uint)
  (assignee principal))
  (let ((recommendation (unwrap! (map-get? safety-recommendations { recommendation-id: recommendation-id }) ERR-RECOMMENDATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? safety-officers tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (default-to false (map-get? safety-officers assignee)) ERR-NOT-AUTHORIZED)

      (ok (map-set safety-recommendations
        { recommendation-id: recommendation-id }
        (merge recommendation {
          assigned-to: (some assignee),
          status: "assigned"
        })
      ))
    )
  )
)

(define-public (implement-recommendation
  (recommendation-id uint))
  (let ((recommendation (unwrap! (map-get? safety-recommendations { recommendation-id: recommendation-id }) ERR-RECOMMENDATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (is-eq (some tx-sender) (get assigned-to recommendation)))
                ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status recommendation) "assigned") ERR-INVALID-STATUS)

      (ok (map-set safety-recommendations
        { recommendation-id: recommendation-id }
        (merge recommendation {
          implementation-date: (some block-height),
          status: "implemented"
        })
      ))
    )
  )
)

;; Investigation Completion Functions
(define-public (complete-investigation
  (investigation-id uint)
  (final-report (string-ascii 1000)))
  (let ((investigation (unwrap! (map-get? investigations { investigation-id: investigation-id }) ERR-INVESTIGATION-NOT-FOUND)))
    (begin
      (asserts! (is-eq tx-sender (get lead-investigator investigation)) ERR-NOT-AUTHORIZED)
      (asserts! (> (len final-report) u0) ERR-INVALID-INPUT)

      (ok (map-set investigations
        { investigation-id: investigation-id }
        (merge investigation {
          status: "completed",
          completion-date: (some block-height),
          final-report: (some final-report)
        })
      ))
    )
  )
)

;; Query Functions
(define-read-only (get-investigation (investigation-id uint))
  (map-get? investigations { investigation-id: investigation-id })
)

(define-read-only (get-evidence (evidence-id uint))
  (map-get? evidence-items { evidence-id: evidence-id })
)

(define-read-only (get-recommendation (recommendation-id uint))
  (map-get? safety-recommendations { recommendation-id: recommendation-id })
)

(define-read-only (get-team-member (investigation-id uint) (investigator principal))
  (map-get? investigation-team { investigation-id: investigation-id, investigator: investigator })
)

(define-read-only (is-authorized-investigator (investigator principal))
  (default-to false (map-get? authorized-investigators investigator))
)

(define-read-only (is-safety-officer (officer principal))
  (default-to false (map-get? safety-officers officer))
)

(define-read-only (get-next-investigation-id)
  (var-get next-investigation-id)
)

(define-read-only (get-next-evidence-id)
  (var-get next-evidence-id)
)

(define-read-only (get-next-recommendation-id)
  (var-get next-recommendation-id)
)
