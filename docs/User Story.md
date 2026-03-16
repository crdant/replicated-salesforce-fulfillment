# Self-Service Trial Workflow: End-to-End Analysis

**Last updated:** 2026-03-05
**Status:** Ready for reassessment once custom metrics threshold alerting ships

## Desired End State

As a vendor, I want a fully automated self-service trial experience where:

1. A "Try It Now" button on my website leads to a branded sign-up page
2. I'm notified when a prospect signs up
3. I'm notified when they activate their account
4. I know when they download/pull my software
5. My sales team has CRM visibility into the customer and their trial expiration
6. I'm notified ahead of the trial license expiring
7. I can see how the customer is using my product (custom metrics, check-ins)
8. When the trial expires, the customer loses access to my software

## How It Maps to Replicated Features Today

### 1. Branded Sign-Up Page

**Available today.** Self-service signup via the Enterprise Portal.

- Vendor configures a default license policy (type, channel, expiration, entitlements)
- Each app gets a dedicated sign-up URL to embed on the vendor website
- Prospect enters company name and email
- Docs: https://docs.replicated.com/vendor/enterprise-portal-self-serve-signup

### 2. Notified on New Signup

**Available today.** Event Notifications webhook.

- **Event:** `New pending self-service signup`
- Fires when a prospect submits the sign-up form (before email confirmation)
- Delivered via webhook to any endpoint (CRM, Slack, Zapier, custom)
- Webhooks support custom auth headers (up to 5) and HMAC-SHA256 signature verification
- Docs: https://docs.replicated.com/vendor/event-notifications-webhooks

### 3. Notified on Account Activation

**Available today.** Event Notifications webhook.

- **Event:** `customer.created`
- Fires when the prospect confirms their email (enters 12-digit verification code), which creates the customer record
- Two-step notification flow:
  1. Form submitted → `new pending self-service signup`
  2. Email confirmed → `customer.created`
- Both delivered via webhook

### 4. Know About Downloads

**Available today.** Event Notifications webhook + instance reporting.

- **Event:** `Customer release asset downloads` fires via webhook
- Instance check-in data reported automatically every 4 hours (or on status changes/updates)
- Visible in Vendor Portal Instance Details
- Docs: https://docs.replicated.com/vendor/instance-insights-event-data

### 5. CRM Visibility + Trial Expiration

**Available today.** Two complementary mechanisms:

- **Real-time:** Webhooks push events (`customer.created`, downloads, license expiring, etc.) directly to CRM endpoints with custom auth headers
- **Batch:** CSV or JSON export of 60+ fields (including license expiration) via Vendor API v3 for bulk sync to Salesforce, Gainsight, Snowflake, etc.
- Docs: https://docs.replicated.com/vendor/instance-data-export

### 6. Notified Ahead of License Expiring

**Available today.** Event Notifications webhook.

- **Event:** `Customer License Expiring`
- Time-based warning with a configurable **days-until-expiration** trigger
- Delivered via webhook so sales gets an automated alert as the trial winds down

### 7. Product Usage Visibility

**Available today (metrics) + coming soon (threshold alerting).**

**Today:**
- App sends custom metrics via POST/PATCH to `http://replicated:3000/api/v1/app/custom-metrics`
- Supports numbers, strings, booleans; displayed in Instance Details with time-series graphs
- Data exportable via Vendor API v3 `/app/{app_id}/events` endpoint
- Docs: https://docs.replicated.com/vendor/custom-metrics

**Coming soon — Custom metrics threshold notifications:**
- In-progress PR: https://github.com/replicatedhq/vandoor/pull/9118
- Adds alerting when metrics cross defined thresholds
- Supports numbers, strings, bools, and null values
- Three notification modes: **send once**, **when updated**, **send always**
- Enables use cases like: notify sales when `active_users > 10` or `sso_enabled` becomes `true`
- **Reassess this workflow once this ships**

### 8. Access Revoked on Trial Expiry

**Available today.**

- **Automatic:** Expired licenses cannot pull images from the proxy registry or pull Helm charts — blocks new installs and upgrades
- **Custom enforcement:** App queries `expires_at` via the Replicated SDK API to enforce in-app restrictions (block login, show upgrade banner, disable features, etc.)
- Docs: https://docs.replicated.com/vendor/licenses-about

## Summary Table

| Step | Available? | Mechanism |
|---|---|---|
| Branded sign-up page | Yes | Self-service signup |
| Notified on signup | Yes | `pending self-service signup` → webhook |
| Notified on activation | Yes | `customer.created` → webhook |
| Know about downloads | Yes | `asset downloaded` → webhook + instance check-ins |
| CRM visibility | Yes | Webhooks (real-time) + API export (batch) |
| Notified before expiry | Yes | `license expiring` → webhook (configurable days) |
| See product usage | Yes | Custom metrics + instance check-ins |
| Usage-based alerts | Soon | Custom metrics threshold notifications (in PR) |
| Access revoked on expiry | Yes | Auto (registry) + custom (SDK API) |

## TODO

- [ ] Reassess once custom metrics threshold alerting is available
- [ ] Validate webhook → CRM integration end-to-end (e.g., Salesforce or HubSpot)
- [ ] Determine what custom metrics the vendor's app should report for sales-relevant signals
- [ ] Decide on in-app license enforcement behavior (hard block vs. degraded mode vs. upgrade banner)