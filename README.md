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
- **Authentication**: Initial login or account creation **requires an active internet connection** to verify credentials against Supabase.
- **Post-Login**: Once logged in, you can create, edit, and view logs entirely offline. Data will automatically synchronize when internet access is restored.
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

---
*Built with ❤️ to empower the next generation of professionals.*
