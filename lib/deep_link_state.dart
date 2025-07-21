/// Global state for pending deep link redirects.
///
/// When a mechanic referral link is opened while the user is logged out,
/// the mechanicId is stored here until after login.
library deep_link_state;

/// Mechanic ID extracted from a referral link when the user isn't logged in.
String? pendingRedirectMechanicId;
