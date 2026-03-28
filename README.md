# 💡 Royal Light — Store Management System

A Flutter web application for managing the Royal Light store in Tira. Built with Flutter + Supabase.

## Features

- **Dashboard** — Overview of store activity
- **Customers** — Manage customer records and details
- **Orders** — Create, track, and manage customer orders with status updates
- **Payments** — Track and record payments
- **Assemblies** — Manage product assembly tasks
- **Fixing** — Track repair/fixing jobs
- **Suppliers** — Manage supplier information

## Prerequisites

Before you start, make sure the following are installed on your PC:

### 1. Install Flutter SDK

Download and install Flutter from: https://docs.flutter.dev/get-started/install

> **Minimum required version:** Flutter 3.41+ / Dart 3.11+

After installing, run this in your terminal to verify:
```bash
flutter --version
```

### 2. Enable Flutter Web Support
```bash
flutter config --enable-web
```

### 3. Install Google Chrome
The app runs in Chrome. Download from: https://www.google.com/chrome/

## Setup Instructions

### Step 1: Clone the Repository
```bash
git clone https://github.com/KhalidKhaskia/royal-lights.git
cd royal-lights
```

### Step 2: Install Dependencies
```bash
flutter pub get
```

### Step 3: Run the Application
```bash
flutter run -d chrome
```

The app will open automatically in Google Chrome.

## Login

Use the username and password provided to you by the admin.

- **Username**: (provided by admin)
- **Password**: (provided by admin)

> Password must be at least 6 characters.

## Project Structure

```
lib/
├── config/           # App theme & Supabase configuration
├── l10n/             # Localization files (Hebrew, Arabic, English)
├── models/           # Data models (Order, Customer, Payment, etc.)
├── providers/        # Riverpod state management providers
├── screens/          # All app screens
│   ├── assemblies/   # Assembly management
│   ├── customers/    # Customer management
│   ├── fixing/       # Fixing/repair management
│   ├── orders/       # Order management
│   ├── payments/     # Payment management
│   └── suppliers/    # Supplier management
├── services/         # Supabase database services
├── widgets/          # Shared widgets (app shell, navigation)
└── main.dart         # App entry point
```

## Tech Stack

| Technology | Purpose |
|---|---|
| **Flutter** | UI framework (Web) |
| **Dart** | Programming language |
| **Supabase** | Backend (Auth, Database, Storage) |
| **Riverpod** | State management |
| **Google Fonts** | Typography (Assistant font) |

## Troubleshooting

### "flutter" command not found
Make sure Flutter is added to your system PATH. See: https://docs.flutter.dev/get-started/install

### App shows a blank white screen
Run a clean build:
```bash
flutter clean
flutter pub get
flutter run -d chrome
```

### Login not working
- Check your internet connection (the app needs Supabase access)
- Make sure your username and password are correct
- Password must be at least 6 characters

### Port already in use
If you get a port conflict, kill the existing process or use a different port:
```bash
flutter run -d chrome --web-port=8080
```

## Development

To run in debug mode with hot reload:
```bash
flutter run -d chrome
```

Press `r` in the terminal for **hot reload**, or `R` for **hot restart**.

---

© 2024 Royal Light Store — Tira
