;; Crowdfunding Platform Smart Contract

;; Constants for error handling
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_CAMPAIGN_ENDED (err u104))
(define-constant ERR_GOAL_NOT_REACHED (err u105))
(define-constant ERR_CAMPAIGN_NOT_ENDED (err u106))
(define-constant ERR_ALREADY_CLAIMED (err u107))
(define-constant ERR_NO_REFUND_AVAILABLE (err u108))
(define-constant ERR_INVALID_MILESTONE (err u109))
(define-constant ERR_MILESTONE_NOT_APPROVED (err u110))

;; Data Variables
(define-data-var admin principal tx-sender)
(define-data-var platform-fee uint u20) ;; 2% platform fee (multiply by 0.001)
(define-data-var campaign-count uint u0)

;; Data Maps
(define-map Campaigns
    uint  ;; campaign ID
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        goal: uint,
        deadline: uint,
        raised: uint,
        claimed: bool,
        status: (string-ascii 20),  ;; active, successful, failed, cancelled
        milestones: (list 5 {
            description: (string-ascii 100),
            amount: uint,
            released: bool,
            approved: bool
        })
    }
)

(define-map CampaignContributions
    {campaign-id: uint, contributor: principal}
    {amount: uint, refunded: bool}
)

;; Read-only functions

;; Get campaign details
(define-read-only (get-campaign (campaign-id uint))
    (map-get? Campaigns campaign-id)
)

;; Get contribution details
(define-read-only (get-contribution (campaign-id uint) (contributor principal))
    (map-get? CampaignContributions {campaign-id: campaign-id, contributor: contributor})
)

;; Check if campaign exists
(define-read-only (campaign-exists (campaign-id uint))
    (is-some (map-get? Campaigns campaign-id))
)

;; Calculate platform fee
(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee)) u1000)
)
;; Public functions

;; Create a new campaign
(define-public (create-campaign (title (string-ascii 100))
                              (description (string-ascii 500))
                              (goal uint)
                              (duration uint)
                              (milestones (list 5 {
                                  description: (string-ascii 100),
                                  amount: uint,
                                  released: bool,
                                  approved: bool
                              })))
    (let ((campaign-id (+ (var-get campaign-count) u1))
          (deadline (+ block-height duration)))
        (if (> goal u0)
            (begin
                (map-set Campaigns campaign-id
                    {
                        creator: tx-sender,
                        title: title,
                        description: description,
                        goal: goal,
                        deadline: deadline,
                        raised: u0,
                        claimed: false,
                        status: "active",
                        milestones: milestones
                    })
                (var-set campaign-count campaign-id)
                (ok campaign-id))
            (err u1)))
)
