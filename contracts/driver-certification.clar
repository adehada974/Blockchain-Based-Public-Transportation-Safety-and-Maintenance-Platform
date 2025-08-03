;; Driver Certification Tracking Contract
;; Monitors commercial driver licenses, training, and safety records

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-DRIVER-NOT-FOUND (err u201))
(define-constant ERR-INVALID-INPUT (err u202))
(define-constant ERR-CERTIFICATION-EXISTS (err u203))
(define-constant ERR-CERTIFICATION-NOT-FOUND (err u204))
(define-constant ERR-EXPIRED-CERTIFICATION (err u205))

;; Data Variables
(define-data-var next-training-id uint u1)

;; Data Maps
(define-map drivers
  { driver: principal }
  {
    name: (string-ascii 100),
    registration-date: uint,
    status: (string-ascii 20),
    total-violations: uint,
    last-training: uint
  }
)

(define-map certifications
  { driver: principal, cert-type: (string-ascii 30) }
  {
    issue-date: uint,
    expiration-date: uint,
    issuing-authority: (string-ascii 50),
    status: (string-ascii 20),
    renewal-count: uint
  }
)

(define-map training-records
  { training-id: uint }
  {
    driver: principal,
    training-type: (string-ascii 50),
    completion-date: uint,
    instructor: principal,
    score: uint,
    status: (string-ascii 20)
  }
)

(define-map safety-violations
  { driver: principal, violation-id: uint }
  {
    violation-type: (string-ascii 50),
    date: uint,
    severity: uint,
    description: (string-ascii 200),
    resolved: bool
  }
)

(define-map authorized-trainers principal bool)
(define-map certification-authorities principal bool)

;; Authorization Functions
(define-public (add-authorized-trainer (trainer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-trainers trainer true))
  )
)

(define-public (add-certification-authority (authority principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set certification-authorities authority true))
  )
)

;; Driver Registration Functions
(define-public (register-driver
  (driver principal)
  (name (string-ascii 100)))
  (begin
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (default-to false (map-get? certification-authorities tx-sender)))
              ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? drivers { driver: driver })) ERR-DRIVER-NOT-FOUND)

    (ok (map-set drivers
      { driver: driver }
      {
        name: name,
        registration-date: block-height,
        status: "active",
        total-violations: u0,
        last-training: u0
      }
    ))
  )
)

;; Certification Management Functions
(define-public (issue-certification
  (driver principal)
  (cert-type (string-ascii 30))
  (expiration-date uint)
  (issuing-authority (string-ascii 50)))
  (begin
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (default-to false (map-get? certification-authorities tx-sender)))
              ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? drivers { driver: driver })) ERR-DRIVER-NOT-FOUND)
    (asserts! (> (len cert-type) u0) ERR-INVALID-INPUT)
    (asserts! (> expiration-date block-height) ERR-INVALID-INPUT)
    (asserts! (> (len issuing-authority) u0) ERR-INVALID-INPUT)

    (let ((existing-cert (map-get? certifications { driver: driver, cert-type: cert-type })))
      (ok (map-set certifications
        { driver: driver, cert-type: cert-type }
        {
          issue-date: block-height,
          expiration-date: expiration-date,
          issuing-authority: issuing-authority,
          status: "active",
          renewal-count: (match existing-cert
            some-cert (+ (get renewal-count some-cert) u1)
            u0)
        }
      ))
    )
  )
)

(define-public (renew-certification
  (driver principal)
  (cert-type (string-ascii 30))
  (new-expiration-date uint))
  (let ((cert (unwrap! (map-get? certifications { driver: driver, cert-type: cert-type }) ERR-CERTIFICATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? certification-authorities tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (> new-expiration-date block-height) ERR-INVALID-INPUT)

      (ok (map-set certifications
        { driver: driver, cert-type: cert-type }
        (merge cert {
          issue-date: block-height,
          expiration-date: new-expiration-date,
          status: "active",
          renewal-count: (+ (get renewal-count cert) u1)
        })
      ))
    )
  )
)

(define-public (suspend-certification
  (driver principal)
  (cert-type (string-ascii 30)))
  (let ((cert (unwrap! (map-get? certifications { driver: driver, cert-type: cert-type }) ERR-CERTIFICATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? certification-authorities tx-sender)))
                ERR-NOT-AUTHORIZED)

      (ok (map-set certifications
        { driver: driver, cert-type: cert-type }
        (merge cert { status: "suspended" })
      ))
    )
  )
)

;; Training Management Functions
(define-public (record-training
  (driver principal)
  (training-type (string-ascii 50))
  (score uint))
  (let ((training-id (var-get next-training-id))
        (driver-data (unwrap! (map-get? drivers { driver: driver }) ERR-DRIVER-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? authorized-trainers tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len training-type) u0) ERR-INVALID-INPUT)
      (asserts! (<= score u100) ERR-INVALID-INPUT)

      ;; Record training
      (map-set training-records
        { training-id: training-id }
        {
          driver: driver,
          training-type: training-type,
          completion-date: block-height,
          instructor: tx-sender,
          score: score,
          status: (if (>= score u70) "passed" "failed")
        }
      )

      ;; Update driver's last training date
      (map-set drivers
        { driver: driver }
        (merge driver-data { last-training: block-height })
      )

      (var-set next-training-id (+ training-id u1))
      (ok training-id)
    )
  )
)

;; Safety Violation Functions
(define-public (record-violation
  (driver principal)
  (violation-type (string-ascii 50))
  (severity uint)
  (description (string-ascii 200)))
  (let ((driver-data (unwrap! (map-get? drivers { driver: driver }) ERR-DRIVER-NOT-FOUND))
        (violation-id (get total-violations driver-data)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? certification-authorities tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len violation-type) u0) ERR-INVALID-INPUT)
      (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-INPUT)
      (asserts! (> (len description) u0) ERR-INVALID-INPUT)

      ;; Record violation
      (map-set safety-violations
        { driver: driver, violation-id: violation-id }
        {
          violation-type: violation-type,
          date: block-height,
          severity: severity,
          description: description,
          resolved: false
        }
      )

      ;; Update driver's total violations
      (map-set drivers
        { driver: driver }
        (merge driver-data {
          total-violations: (+ violation-id u1),
          status: (if (>= (+ violation-id u1) u5) "suspended" (get status driver-data))
        })
      )

      (ok violation-id)
    )
  )
)

(define-public (resolve-violation
  (driver principal)
  (violation-id uint))
  (let ((violation (unwrap! (map-get? safety-violations { driver: driver, violation-id: violation-id }) ERR-CERTIFICATION-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? certification-authorities tx-sender)))
                ERR-NOT-AUTHORIZED)

      (ok (map-set safety-violations
        { driver: driver, violation-id: violation-id }
        (merge violation { resolved: true })
      ))
    )
  )
)

;; Query Functions
(define-read-only (get-driver (driver principal))
  (map-get? drivers { driver: driver })
)

(define-read-only (get-certification (driver principal) (cert-type (string-ascii 30)))
  (map-get? certifications { driver: driver, cert-type: cert-type })
)

(define-read-only (get-training-record (training-id uint))
  (map-get? training-records { training-id: training-id })
)

(define-read-only (get-violation (driver principal) (violation-id uint))
  (map-get? safety-violations { driver: driver, violation-id: violation-id })
)

(define-read-only (is-certification-valid (driver principal) (cert-type (string-ascii 30)))
  (match (map-get? certifications { driver: driver, cert-type: cert-type })
    some-cert (and
                (is-eq (get status some-cert) "active")
                (> (get expiration-date some-cert) block-height))
    false)
)

(define-read-only (is-authorized-trainer (trainer principal))
  (default-to false (map-get? authorized-trainers trainer))
)

(define-read-only (is-certification-authority (authority principal))
  (default-to false (map-get? certification-authorities authority))
)

;; Driver Status Functions
(define-public (update-driver-status
  (driver principal)
  (new-status (string-ascii 20)))
  (let ((driver-data (unwrap! (map-get? drivers { driver: driver }) ERR-DRIVER-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                    (default-to false (map-get? certification-authorities tx-sender)))
                ERR-NOT-AUTHORIZED)
      (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

      (ok (map-set drivers
        { driver: driver }
        (merge driver-data { status: new-status })
      ))
    )
  )
)
