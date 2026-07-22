# Internship/Industrial Attachment Management System

A professional, hybrid **offline-first** mobile application built with Flutter to streamline the internship and industrial attachment process for Students, Supervisors, and Institution Administrators.

## 🚀 About the Application
This application is designed to solve the challenges of tracking student progress during industrial attachments, especially in environments with intermittent internet connectivity. It provides a robust, digital alternative to physical logbooks, ensuring data integrity through local storage (SQLite) and seamless cloud synchronization (Supabase).

## ✨ Key Features

### 👨‍🎓 For Students
- **Daily Logbook Management**: Record daily work descriptions and knowledge acquired.
- **AI Log Professionalizer ✨**: An inbuilt AI bot that helps students refine their vocabulary and correct grammar in log entries.
- **Progress Tracking**: Visual progress bars and analytics cards showing Approved, Pending, and Rejected logs at a glance.
- **Official PDF Reports**: Generate professionally branded PDF logbook reports containing the **School Logo**, institution name, student level, and institutional ID.
- **Supervisor Selection**: Secure onboarding flow to select assigned Academic and Industry supervisors from a verified directory.

### 👨‍🏫 For Supervisors (Academic & Industry)
- **Log Evaluation**: Review, Grade, and Approve student logs from a dedicated, reactive portal.
- **Qualitative Feedback**: Provide specific recommendations and comments on daily entries that students can see instantly.
- **Student Management**: View assigned student lists and unassign students in case of selection errors.
- **Real-time Metrics**: Dynamic counts of pending logs requiring attention.

### 🔑 For Institution Administrators
- **System Configuration**: Define global parameters like the required number of log entries and the official Institution Name.
- **Company Profiles**: Full CRUD management for participating industrial partners and companies.
- **Allocation Oversight**: Monitor the matching of students to Academic and Industry staff.

## 🛠 Technical Architecture

### **Reactive State Management**
The application utilizes **Riverpod** for a truly reactive experience. We've replaced legacy polling with `StreamProviders` that centrally monitor the local SQLite database. This means:
- UI updates instantly when logs are approved or submitted.
- Dashboard statistics stay in sync without manual refreshes.
- Memory usage is optimized by preventing redundant rebuild loops.

### **Advanced Synchronization Service**
Our `SyncService` implements a robust hybrid strategy:
- **Offline-First**: All data is saved locally first, ensuring functionality in remote areas.
- **Field-Level Merging**: Uses `updated_at` timestamps to perform a "Cloud-wins" merge, but preserves local-only metadata like `local_path` for media.
- **Automatic Sync**: Triggers automatically upon network detection using `connectivity_plus`.
- **Reliability**: Includes a 3-tier retry mechanism with exponential backoff.

#### **💡 Important Note on Offline Usage**
- **Authentication**: Initial account creation **requires an active internet connection**. However, once a user has successfully logged in once on a device, the system caches their credentials locally.
- **Cached Login (Offline Wins! ⚡)**: The application utilizes a highly optimized **"Offline Wins"** architecture. Launching the app offline instantly routes previously authenticated users straight to their dashboard (0ms startup latency) without any loading hangs or timeouts. On the login screen, offline attempts bypass online timeouts completely and verify credentials instantly against local DB caches.
- **Post-Login**: Once logged in, students, supervisors, and admins can perform daily logging, view histories, edit profiles, assign/unassign supervisors, and manage students completely offline.
- **Non-blocking Operations**: All supervisor unassignment and student roster toggles operate in an offline-first, non-blocking flow. They execute immediately on local databases and safely schedule background/sync queue operations.
- **Manual Sync**: You can also trigger a manual synchronization by clicking the sync icon on the dashboard or using "Pull-to-refresh".

### **AI-Powered Productivity**
The `AIService` leverages heuristic-based professionalization to help students translate "casual" notes into "formal" industrial reports. It handles:
- Professional vocabulary mapping.
- Automatic sentence casing and terminal punctuation.
- Context-aware prefixing for brief entries.

## 📋 Technical Requirements
- **Flutter SDK**: ^3.11.0
- **Supabase**: Cloud backend for Auth, Database (PostgreSQL), and Storage.
- **SQLite**: (Sqflite) for high-performance local persistence.
- **Material 3**: Modern design system implementation.

## ⚙️ Setup & Installation
1. **Clone the repository.**
2. **Supabase Setup**: Run the provided `supabase_schema.sql` in your Supabase SQL Editor.
3. **Configuration**: Update `lib/core/config/supabase_config.dart` with your project URL and Anon Key.
4. **Assets**: Ensure `assets/images/logo.png` is present for PDF branding.
5. **Run**: `flutter pub get` followed by `flutter run`.

## 🔄 Application Workflow

### **1. Secure Authentication**
- **Sign Up**: New users create an account by providing their details (Name, Institutional ID, Level) and selecting a role (Student, Supervisor, or Admin).
- **Login**: Existing users sign in with their email and password. **Note**: Initial authentication requires internet access.
- **Session Management**: The app uses reactive providers to monitor auth state. When a user logs in, the navigation stack is reset, and they are directed to their specific dashboard based on their role.

### **2. Role-Based Navigation**
- **Student Dashboard**: Provides an overview of logbook progress, quick access to create new entries, and a summary of recent activities.
- **Supervisor Dashboard**: Allows for reviewing student logs, providing feedback, and grading entries.
- **Admin Dashboard**: Facilitates system-wide configurations and management of companies and user allocations.

### **3. Offline-First Logbook Management**
- **Daily Logging**: Students record their work and knowledge gained. If offline, the data is saved to the local SQLite database and marked as "dirty".
- **AI Professionalizer**: Students can use the AI bot to refine their logs into formal reports.
- **Media Attachments**: Photos can be attached to logs and are queued for upload once a connection is available.

### **4. Synchronization**
- **Automatic Sync**: The app monitors connectivity. When back online, it pushes local "dirty" changes to the cloud and pulls the latest updates using a "Cloud-wins" merging strategy.
- **Manual Sync**: Users can trigger a manual sync via the sync icon on the dashboard to ensure their data is up to date immediately.

### **5. Reporting & Export**
- **PDF Generation**: Students can export their logs into a professionally branded PDF report, including the institutional logo and formatted tables.

### **6. Secure Sign Out**
- **Sign Out**: Users can securely sign out via the main drawer. This wipes the active session and returns the user to the login screen, ensuring data privacy on shared devices.

## ⛓️ Internal Architecture & Component Connectivity

To guarantee maximum responsiveness and complete reliability in offline/online states, the application uses a highly interconnected multi-tier architecture. Below is a detailed map of how these internal components interact:

```
┌────────────────────────────────────────────────────────────────────────┐
│                              Flutter UI                                │
│          (Student Dashboard, Supervisor Portal, Admin Panel)           │
└───────┬───────────────────────────▲───────────────────────────▲────────┘
        │ Read/Write (via Riverpod) │ Watch Streams             │ Fast-Read
        ▼                           │                           │
┌───────────────────────────────┐   │                   ┌───────┴────────┐
│      Riverpod Providers       │───┼──────────────────►│ Shared Prefs   │
│ (userProfileProvider, etc.)   │   │                   │ (0ms Role/Name │
└───────┬───────────────────────┘   │                   │  Onstart Cache)│
        │                           │                   └────────────────┘
        ▼ Write (Offline Wins)      │ Watch DB Streams
┌───────────────────────────────────┴────────────────────────────────────┐
│                       SQLite Local Database (Sqflite)                  │
│       - profiles  - log_entries  - companies  - app_settings           │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Push/Pull (Sync Queue)
                        ┌───────────┴───────────┐
                        │      SyncService      │
                        │ (connectivity_plus)   │
                        └───────────┬───────────┘
                                    │ Supabase Network API
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                            Supabase Cloud Backend                      │
│                  - Auth  - Storage  - Postgres Tables                  │
└────────────────────────────────────────────────────────────────────────┘
```

### **1. State Management & Real-Time Rebuilding (Riverpod)**
- **Reactivity Hub**: Riverpod acts as the reactive data controller. Components like the Student Dashboard or Supervisor Student List do not query databases directly on every frame. Instead, they watch custom Riverpod providers (`currentUserLogsProvider`, `supervisorStudentsProvider`, `userProfileProvider`).
- **Instant Invalidation**: Whenever a local write occurs (e.g. submitting a log or completing onboarding), the UI calls `ref.invalidate(...)` on the relevant provider. This forces immediate local SQLite re-evaluation, pushing refreshed, calculated states to the UI in less than **16ms** (60fps).

### **2. Ultra-Fast Cold Startup (SharedPreferences)**
- **Startup Bypass**: A major problem with hybrid apps is the cold startup lag where the screen stays blank waiting for database initialization. To solve this, key session properties (`user_role_{id}`, `user_name_{id}`, `offline_user_email`) are written directly to `SharedPreferences` at sign-in.
- **Immediate Navigation**: On launch, the `appRouteStateProvider` and `userProfileProvider` read SharedPreferences synchronously. If session markers are present, the user is instantly routed straight to their role-specific dashboard with **0ms startup delay**, while SQLite and Supabase are queried asynchronously in the background.

### **3. Performance SQLite Persistence (Sqflite)**
- **Unified Tables**: SQLite acts as the single source of truth for the frontend UI.
- **Tracking Schema**: Every record in the local database contains `is_dirty` (bool/int) and `is_deleted` (bool/int) tracking columns.
  - `is_dirty = 1`: Marks records created or modified offline that are waiting to be uploaded to the cloud.
  - `is_deleted = 1`: Marks records soft-deleted locally that are waiting to be hard-deleted on the cloud and locally upon sync.

### **4. Automatic Synchronization Queue (SyncService)**
- **Network Listener**: The `SyncService` uses `connectivity_plus` to monitor internet connections. When an active network is detected, it triggers `syncData()`.
- **Two-Way Merging (Offline Wins)**:
  - **Push (Upload)**: Scans SQLite for any record with `is_dirty = 1`. If `is_deleted = 1`, it executes a cloud hard-delete and then removes the row from SQLite. Otherwise, it strips local-only fields (`email`, `password_hash`) and uploads/upserts the record to Supabase, then resets `is_dirty = 0`.
  - **Pull (Download)**: Pulls remote updates since the last synchronization timestamp. If a pulled cloud ID is already marked `is_dirty` or `is_deleted` locally, **the pull skips overwriting that record (Offline Wins)**, ensuring your local, offline changes are never corrupted or reverted by the cloud.

### **5. Robust Cascading Deletions Architecture**
- **Data Integrity**: Deleting accounts previously left corrupted associations or dangling references. The system now enforces high-performance, automated cascading triggers inside the local SQLite manager:
  - **Deleting a Student**: Automatically cascades soft-deletions to all corresponding daily logs and media attachments in both local and remote tables via `is_deleted = 1` and `is_dirty = 1`.
  - **Deleting a Supervisor**: Automatically updates associated student profiles, clearing out `supervisor_id` or `industry_supervisor_id` instantly, so students are cleanly prompted to assign a replacement.

---
*Built with ❤️ to empower the next generation of professionals.*
