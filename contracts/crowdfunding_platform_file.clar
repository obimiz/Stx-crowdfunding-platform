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

;; Contribute to a campaign
(define-public (contribute (campaign-id uint))
    (let ((amount (stx-get-balance tx-sender))
          (campaign (unwrap! (map-get? Campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
          (current-contribution (default-to {amount: u0, refunded: false}
                                         (map-get? CampaignContributions 
                                                  {campaign-id: campaign-id, contributor: tx-sender}))))
        (if (and
                (is-eq (get status campaign) "active")
                (< block-height (get deadline campaign)))
            (begin
                ;; Transfer STX
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                
                ;; Update campaign
                (map-set Campaigns campaign-id
                    (merge campaign 
                          {raised: (+ (get raised campaign) amount)}))
                
                ;; Update contribution record
                (map-set CampaignContributions 
                        {campaign-id: campaign-id, contributor: tx-sender}
                        {amount: (+ (get amount current-contribution) amount),
                         refunded: false})
                (ok true))
            ERR_CAMPAIGN_ENDED))
)

;; Claim funds (for campaign creator)
(define-public (claim-funds (campaign-id uint))
    (let ((campaign (unwrap! (map-get? Campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND)))
        (if (and
                (is-eq tx-sender (get creator campaign))
                (>= (get raised campaign) (get goal campaign))
                (>= block-height (get deadline campaign))
                (not (get claimed campaign)))
            (begin
                (let ((platform-fee-amount (calculate-platform-fee (get raised campaign)))
                      (creator-amount (- (get raised campaign) platform-fee-amount)))
                    ;; Transfer platform fee
                    (try! (as-contract (stx-transfer? platform-fee-amount tx-sender (var-get admin))))
                    ;; Transfer funds to creator
                    (try! (as-contract (stx-transfer? creator-amount tx-sender (get creator campaign))))
                    ;; Update campaign status
                    (map-set Campaigns campaign-id
                        (merge campaign 
                              {claimed: true,
                               status: "successful"}))
                    (ok true)))
            ERR_NOT_AUTHORIZED))
)

;; Admin Functions

;; Update platform fee
(define-public (update-platform-fee (new-fee uint))
    (if (is-eq tx-sender (var-get admin))
        (begin
            (var-set platform-fee new-fee)
            (ok true))
        ERR_NOT_AUTHORIZED)
)

;; Change admin
(define-public (change-admin (new-admin principal))
    (if (is-eq tx-sender (var-get admin))
        (begin
            (var-set admin new-admin)
            (ok true))
        ERR_NOT_AUTHORIZED)
)

;; Cancel campaign (only by creator or admin)
(define-public (cancel-campaign (campaign-id uint))
    (let ((campaign (unwrap! (map-get? Campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND)))
        (if (or (is-eq tx-sender (get creator campaign))
                (is-eq tx-sender (var-get admin)))
            (begin
                (map-set Campaigns campaign-id
                    (merge campaign {status: "cancelled"}))
                (ok true))
            ERR_NOT_AUTHORIZED))
)
