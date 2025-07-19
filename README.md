# SkipTow

SkipTow is a cross-platform mobile and web app for requesting mobile mechanic services. Customers can find mechanics nearby, message them, and submit service requests without needing a tow truck. Mechanics can set their availability, define their working radius, and receive service requests directly from customers.

SkipTow is open source right now for ease-of-contributions from community and LLM, however the project may not always be open source in the future.

## Features

### For Customers:
- Interactive map showing nearby mechanics.
- Availability status of mechanics (active or extended radius).
- Submit service requests (invoices) with vehicle and problem details.
- Real-time messaging with mechanics.
- View active and past service requests.
- Custom "my location" button for web.

### For Mechanics:
- Interactive map showing own location, service radius, and active/inactive status.
- Set active/inactive status.
- Define working radius.
- Receive and respond to customer service requests.
- Real-time location updates.
- Wrench icon replaces blue dot when active.

### Technology Stack:
- Flutter (mobile and web)
- Firebase Authentication (user accounts)
- Firebase Firestore (real-time database)
- Firebase Hosting (for web app)
- Google Maps Flutter plugin

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
- role: `"mechanic"` or `"customer"`
- isActive: `true` or `false`
- radiusMiles: number
- location:
  - lat: number
  - lng: number
- timestamp: DateTime

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
- status: `"active"` or `"completed"`

### messages/{conversationId}/threads/{messageId}
- senderId
- recipientId
- text
- timestamp

## Setup Instructions

1. Clone the repository.
2. Run `flutter pub get`.
3. Set up Firebase project and Firebase CLI.
4. Connect Flutter to Firebase using `firebase_options.dart`.
5. For web:
   - Add Google Maps API key in `web/index.html`.
   - Deploy using `firebase deploy`.
6. For Android/iOS:
   - Add Google Maps API key in platform-specific configs.
   - Run using `flutter run`.
7. Deploy Cloud Functions:
   - From the `functions` directory run `npm install`.
   - Deploy using `firebase deploy --only functions`.

## Next Steps (Planned)
- Real-time messaging system (in development).
- Admin dashboard (future feature).
- Payment processing (future feature).
- Improved UI/UX enhancements.
