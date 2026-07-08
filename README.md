# Internship/Industrial Attachment Management System

A professional, hybrid **offline-first** mobile application built with Flutter to streamline the internship and industrial attachment process for Students, Supervisors, and Institution Administrators.

## 🚀 About the Application
This application is designed to solve the challenges of tracking student progress during industrial attachments, especially in environments with intermittent internet connectivity. It provides a robust, digital alternative to physical logbooks, ensuring data integrity through local storage (SQLite) and seamless cloud synchronization (Supabase).

## ✨ Key Features

### 👨‍🎓 For Students
- **Daily Logbook Management**: Record daily work descriptions and knowledge acquired.
- **AI Log Professionalizer ✨**: An inbuilt AI bot that helps students refine their vocabulary and correct grammar in log entries.
- **Progress Tracking**: Visual progress bars showing the number of logs approved against the graduation requirement (e.g., 60 logs).
- **Official PDF Reports**: Generate professionally branded PDF logbook reports containing the school logo, institution name, student level, and ID.
- **Supervisor Selection**: Onboarding flow to select assigned Academic and Industry supervisors.

### 👨‍🏫 For Supervisors (Academic & Industry)
- **Log Evaluation**: Review, Grade, and Approve student logs from a dedicated portal.
- **Qualitative Feedback**: Provide specific recommendations and comments on daily entries.
- **Student Management**: View assigned student lists and unassign students in case of selection errors.
- **Dashboard Stats**: Real-time counts of pending logs requiring attention.

### 🔑 For Institution Administrators
- **System Configuration**: Define global parameters like the required number of log entries and the official Institution Name.
- **Student Allocation**: Oversee and manage the matching of students to Academic staff.
- **Company Profiles**: CRUD management for participating industrial partners and companies.
- **Analytics**: View completion metrics across the entire student population.

### 🛠 Technical Excellence
- **Hybrid Offline/Online Sync**: Sophisticated "Cloud wins" synchronization with field-level conflict resolution based on timestamps.
- **Role-Based Access Control (RBAC)**: Secure isolation of data between Students, Supervisors, and Admins.
- **Watertight Navigation**: Secure session management that clears navigation history on logout to prevent session leakage.
- **Material 3 Design**: A modern, professional user interface with optimized spacing and intuitive layouts.

## 📋 Requirements
- **Flutter SDK**: 3.0.0 or higher
- **Supabase Account**: For backend authentication, database, and storage.
- **SQLite**: (Sqflite) for local data persistence.
- **Permissions**: Internet access and Network state detection.

## ⚙️ How It Works
1. **Authentication**: Users sign up with specific roles. Students provide their institutional ID and current level.
2. **Onboarding**: Students select their Academic and Industry supervisors from the verified staff directory.
3. **Daily Routine**: Students log their work offline. They can use the **AI Bot** to polish their writing.
4. **Synchronization**: When a network is detected, the `SyncService` automatically merges local changes with the cloud.
5. **Review Cycle**: Supervisors receive logs, provide feedback, and approve them.
6. **Finalization**: Admins monitor completion. Students generate their official PDF report for final submission.

---
*Built with ❤️ for a better internship experience.*
