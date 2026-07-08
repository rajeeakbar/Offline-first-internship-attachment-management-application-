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

---
*Built with ❤️ to empower the next generation of professionals.*
