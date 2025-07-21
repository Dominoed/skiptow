# SkipTow

SkipTow is a cross-platform mobile and web app for requesting mobile mechanic services. Customers can locate nearby mechanics, chat with them and submit service requests without needing a tow truck. Mechanics manage their availability, working radius and jobs directly from the app.

SkipTow is currently open source for community contributions; it may become closed source later.

## Features

### Customer Features
- Interactive map of active mechanics with a web "my location" button
- Choose a specific mechanic or request help from *Any Tech*
- Submit service requests with vehicle details, contact info and notes
- Real-time status banners when a mechanic accepts, arrives or completes a job
- Track the mechanic’s live location and view estimated arrival time
- In-app chat thread on each invoice with photo attachments
- View and manage all service requests, invoices and vehicle history
- Receive push notifications for request updates and payment reminders
- Report payment issues after confirming final price
- Optionally tip your mechanic after confirming the final price (placeholder
  payment processing)
- Access a single support page for emergencies, FAQs and direct help
- Manage profile, saved vehicles and account settings

### Mechanic Features
- Toggle active/inactive status and mark temporarily unavailable
- Set working radius using a slider and view it on the map
- Request queue showing nearby jobs to accept or decline
- Map view of own location with wrench icon when active
- Track job progress: confirm arrival, start work and mark completed with final price
- Earnings report and job history with statistics
- Real-time messaging with customers from invoice detail pages
- Notifications for new requests, messages and invoices
- Location history stored automatically while active

### Admin Features
- Admin dashboard with platform statistics and recent activity
- Search and filter invoices by status and date range
- Export invoices and user lists to CSV
- Manage users, view profiles and see flagged or suspicious accounts
- Broadcast messages and notifications to any user
- View and close user reports or disputes
- Financial reporting and basic revenue estimates
- Ability to enable maintenance mode with a custom message
- Automatic cancellation of requests left pending for over six weeks

### General Functionality
- Firebase Authentication and Firestore for real-time data storage
- Firebase Cloud Functions send push notifications for new requests and updates
- Offline banner when connectivity is lost
- Global alerts banner for important announcements
- Step-by-step invoice timeline showing request lifecycle
- Web and Android builds provided by Flutter

## Pro User Features
- Pro customers see all mechanics and bypass normal limits.
- Pro customers can open multiple simultaneous requests, non-pro users can't have more than one open request at a time.
- Pro mechanics can have multiple open requests at once, but non-pro users can't.
- Stripe billing handled externally.

## File Structure
lib/main.dart
lib/pages/
├── login_page.dart
├── signup_page.dart
├── dashboard_page.dart
├── mechanic_dashboard.dart
├── customer_dashboard.dart
├── create_invoice_page.dart
├── messages_page.dart
lib/services/auth_service.dart
firebase_options.dart

## Data Structure (Firestore)

### users/{userId}
- role: `"mechanic"`, `"customer"` or `"admin"`
- isActive: `true` or `false`
- radiusMiles: number
- location:
  - lat: number
  - lng: number
- timestamp: DateTime
- lastActiveAt: timestamp (dashboard updates this when opened)

### invoices/{invoiceId}
- mechanicId
- customerId
- mechanicUsername
- distance
- location (lat/lng)
- carInfo (year/make/model)
- description
- customerPhone
- customerEmail
- timestamp
- status: `"active"`, `"completed"`, `"closed"` or `"cancelled"`
- paymentStatus

### messages/{conversationId}/threads/{messageId}
- senderId
- recipientId
- text
- timestamp

### config/maintenance
- enabled: `true` or `false`
- message: string (optional)

## General Messaging & Support
- Admin can message any user outside of invoices.
- Users can chat with support/admin directly.
- All chats stored in Firestore (`messages_general`).
- Admin receives visual notifications in the admin dashboard.

## Setup Instructions

1. Clone the repository.
2. Run `flutter pub get`.
3. Set up a Firebase project and install the Firebase CLI.
4. Configure `firebase_options.dart` for your Firebase project.
5. For web:
   - Add your Google Maps API key in `web/index.html`.
   - Deploy using `firebase deploy`.
6. For Android/iOS:
   - Add your Google Maps API key in the platform specific config files.
   - Run the app with `flutter run`.
7. Deploy Cloud Functions:
   - From the `functions` directory run `npm install`.
   - Deploy with `firebase deploy --only functions`.

## Next Steps
- Payment processing integration
- Additional UI/UX improvements
