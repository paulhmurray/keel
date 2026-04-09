package billing

import (
	"encoding/json"
	"io"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stripe/stripe-go/v79"
	checkoutsession "github.com/stripe/stripe-go/v79/checkout/session"
	"github.com/stripe/stripe-go/v79/billingportal/session"
	"github.com/stripe/stripe-go/v79/webhook"
)

type Handler struct {
	db *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// Checkout handles POST /billing/checkout
// Creates a Stripe Checkout session for the Solo plan and returns the URL.
func (h *Handler) Checkout(c *gin.Context) {
	userID := c.GetString("userID")

	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
	priceID := os.Getenv("STRIPE_PRICE_ID")

	params := &stripe.CheckoutSessionParams{
		Mode: stripe.String(string(stripe.CheckoutSessionModeSubscription)),
		LineItems: []*stripe.CheckoutSessionLineItemParams{
			{
				Price:    stripe.String(priceID),
				Quantity: stripe.Int64(1),
			},
		},
		ClientReferenceID: stripe.String(userID),
		SuccessURL:        stripe.String("https://keel-app.dev/settings?upgraded=1"),
		CancelURL:         stripe.String("https://keel-app.dev/settings"),
	}

	s, err := checkoutsession.New(params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create checkout session"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": s.URL})
}

// Portal handles GET /billing/portal
// Creates a Stripe billing portal session for the authenticated user.
func (h *Handler) Portal(c *gin.Context) {
	userID := c.GetString("userID")

	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")

	var stripeID *string
	err := h.db.QueryRow(c.Request.Context(),
		`SELECT stripe_id FROM users WHERE id = $1`, userID,
	).Scan(&stripeID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch user"})
		return
	}

	if stripeID == nil || *stripeID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no stripe customer associated with this account"})
		return
	}

	params := &stripe.BillingPortalSessionParams{
		Customer:  stripe.String(*stripeID),
		ReturnURL: stripe.String("https://keel-app.dev/settings"),
	}
	s, err := session.New(params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create billing portal session"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": s.URL})
}

// Webhook handles POST /billing/webhook
// Verifies Stripe signature and processes relevant events.
func (h *Handler) Webhook(c *gin.Context) {
	webhookSecret := os.Getenv("STRIPE_WEBHOOK_SECRET")

	payload, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
		return
	}

	sigHeader := c.GetHeader("Stripe-Signature")
	event, err := webhook.ConstructEvent(payload, sigHeader, webhookSecret)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stripe signature"})
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		var checkoutSession stripe.CheckoutSession
		if err := json.Unmarshal(event.Data.Raw, &checkoutSession); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to parse event data"})
			return
		}
		h.handleCheckoutCompleted(c, &checkoutSession)
		return

	case "customer.subscription.deleted":
		var sub stripe.Subscription
		if err := json.Unmarshal(event.Data.Raw, &sub); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to parse event data"})
			return
		}
		h.handleSubscriptionDeleted(c, &sub)
		return
	}

	// Acknowledge unhandled events
	c.JSON(http.StatusOK, gin.H{"received": true})
}

func (h *Handler) handleCheckoutCompleted(c *gin.Context, cs *stripe.CheckoutSession) {
	if cs.Customer == nil || cs.ClientReferenceID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing customer or client_reference_id"})
		return
	}

	_, err := h.db.Exec(c.Request.Context(),
		`UPDATE users SET plan = 'solo', stripe_id = $1 WHERE id = $2`,
		cs.Customer.ID, cs.ClientReferenceID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user plan"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"received": true})
}

func (h *Handler) handleSubscriptionDeleted(c *gin.Context, sub *stripe.Subscription) {
	if sub.Customer == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing customer"})
		return
	}

	_, err := h.db.Exec(c.Request.Context(),
		`UPDATE users SET plan = 'free' WHERE stripe_id = $1`,
		sub.Customer.ID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user plan"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"received": true})
}
