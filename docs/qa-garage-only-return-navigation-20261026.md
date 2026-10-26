# Garage-only return navigation

The Garage portal auto-opened a workshop but kept the generic ecosystem picker
underneath. Back therefore exposed Create a fleet, Fleet membership, and consumer
bookings inside the Garage entry flow.

When preferredPortal is Garage, the return picker is now branded Flotaryx Garage
and contains only workshop creation and existing workshop/mechanic destinations.
Its navigation guard also refuses Fleet/customer destinations. Generic ecosystem
entry and the Fleet/customer entry flows retain their existing module choices.
This is navigation scope; server membership checks remain the authorization layer.

Regression tests cover canceling first-workshop setup, returning from an existing
workshop with and without Fleet membership, refreshing and reopening the workshop.
They assert that Fleet creation and consumer booking tiles remain absent. Existing
tests retain coverage for the shared picker and customer portal.

Draft source only. Flutter tests and compiled QA artifacts are verified in CI;
Flutter is unavailable locally. No production, Stripe, Supabase schema, account,
subscription, access grant, or deployment changes are part of this PR.
