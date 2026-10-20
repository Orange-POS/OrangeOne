# OrangeONE

**OrangeONE** is a Flutter mobile inventory application for Android and iOS that integrates with **Odoo through JSON-RPC**. It is organized with feature-first Clean Architecture and uses Riverpod for state management.

> **Project status:** Under active development. This README describes the documented implementation and planned work; it does not certify that a live Odoo connection, CI run, or release build has been verified.

## Contents

- [Current scope](#current-scope)
- [Technology stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Run configurations](#run-configurations)
- [Architecture](#architecture)
- [Testing and validation](#testing-and-validation)
- [Continuous integration](#continuous-integration)
- [Security and release notes](#security-and-release-notes)
- [Project documentation](#project-documentation)
- [Development workflow](#development-workflow)

## Current scope

The project documentation describes these milestones:

| Task | Area | Documented scope |
| --- | --- | --- |
| 01 | Foundation | Very Good CLI setup, native flavors, quality checks and CI |
| 02 | Architecture | Feature-first presentation, domain and data layer organization |
| 03 | Initialization | Riverpod async initialization and injected local configuration |
| 04 | Authentication | QR login, Dio/JSON-RPC transport, secure sessions and protected navigation |
| 05 | Barcode lookup | Home scanner, Odoo product lookup and navigation to details or a prefilled draft |
| 07 | Price update | CHF price input, validation, confirmation and server-side checks |
| 08 | Product editing | [Product name and tax workflow](docs/product-edit.md) |
| 09 | Branding | [Startup splash and shared branding](docs/splash-branding.md) |
| 11 | Environments and logging | [Validated settings and safe structured logs](docs/environments-and-logging.md) |
| Testing / Deployment | Reliability and delivery | [Testing strategy](docs/testing.md) |

Product lookup opens details for a matching barcode and the Create New Product form for an unknown barcode. Creation supports the original Odoo save endpoint; the create-only controller enhancement is optional. See [product creation](docs/product-creation.md) for compatibility and permission details. Stock adjustment, offline synchronization, Firebase integrations, the complete inventory dashboard, and signed store distribution remain future work.

## Technology stack

| Area | Technology |
| --- | --- |
| Framework | Flutter / Dart |
| Project bootstrap | Very Good CLI 1.5.0 (core template) |
| Architecture | Feature-first Clean Architecture |
| State and dependency injection | Riverpod |
| Navigation | GoRouter |
| HTTP transport | Dio |
| Backend | Odoo JSON-RPC |
| Session storage | Platform secure storage |
| Automation | GitHub Actions |
| Design reference | [OrangeONE Mobile Design System](https://www.figma.com/design/r6TjxFouED6tJ9fX6evjhz/OrangeONE---Mobile-Design-System?node-id=0-1) |

**Documented SDK versions:** Flutter 3.47.5 stable and Dart 3.13.4. Use the version pinned in the repository's CI configuration if it changes.

**Documented Android build toolchain:** Android Gradle Plugin 8.12.0, Gradle 8.14.3, and Kotlin 2.3.20. Use `flutter doctor -v` to see the JDK actually selected by Flutter.

## Prerequisites

- Flutter SDK and Dart, matching the repository's configured versions.
- VS Code or Android Studio with Flutter and Dart support.
- Android SDK and an Android device/emulator for Android development.
- Xcode on macOS for local iOS compilation; iOS CI builds run on macOS runners.
- Git.
- Access to a compatible Odoo installation and a valid POS-generated QR code for live login tests.

Verify your tools:

```powershell
flutter --version
dart --version
flutter doctor -v
flutter doctor --android-licenses
```

Very Good CLI was used to generate the original project; **you do not need to regenerate the app** to work on this repository.

## Getting started

Clone the repository (or open your existing checkout):

```powershell
git clone https://github.com/AchuthanDev/orangeone.git
cd orangeone
flutter pub get
flutter devices
```

If you already have the project at `C:\Users\Startklar\Pictures\Orangeone`, run `flutter pub get` there instead of cloning it again.

### Run the development app

```powershell
flutter run --flavor development --target lib/main_development.dart
```

Choose a device explicitly when necessary:

```powershell
flutter devices
flutter run --flavor development --target lib/main_development.dart -d DEVICE_ID
```

Replace `DEVICE_ID` with an ID reported by `flutter devices`.

## Run configurations

| Flavor | Entry point | Application / bundle ID |
| --- | --- | --- |
| Development | `lib/main_development.dart` | `com.orangeone.app.dev` |
| Staging | `lib/main_staging.dart` | `com.orangeone.app.stg` |
| Production | `lib/main_production.dart` | `com.orangeone.app` |

```powershell
flutter run --flavor staging --target lib/main_staging.dart
flutter run --flavor production --target lib/main_production.dart
```

Always match the native flavor with its Dart entry point. These identifiers are provisional until ownership is confirmed for store and Firebase registration.

See [environment configuration and logging](docs/environments-and-logging.md) for per-flavor templates, validation, and production logging policy.

### Odoo configuration

The documented login workflow discovers the Odoo host and port from a POS-generated QR code. For local timeout overrides, copy the checked-in example configuration:

```powershell
Copy-Item config/odoo.example.json config/development.local.json
```

Edit the local configuration file and run:

```powershell
flutter run --flavor development --target lib/main_development.dart --dart-define-from-file=config/development.local.json -d DEVICE_ID
```

Do **not** put passwords, tokens, session details or QR payloads in Dart defines, tracked JSON, or source control. Prefer HTTPS for Odoo connections. See [authentication documentation](docs/authentication.md) for the integration contract and platform permissions.

## Architecture

Each business feature is organized into presentation, domain and data layers:

```text
lib/
├── app/                    # App composition and navigation
├── core/                   # Shared non-UI infrastructure
├── shared/                 # Reusable UI components
└── features/
    └── feature_name/
        ├── presentation/
        │   ├── pages/       # Full screens
        │   ├── widgets/     # Reusable feature UI
        │   └── providers/   # Riverpod state and UI coordination
        ├── domain/
        │   ├── entities/    # Business objects
        │   ├── repositories/# Repository contracts
        │   └── use_cases/   # Business operations and rules
        └── data/
            ├── models/      # Serialization and mapping
            ├── data_sources/# APIs and local storage
            └── repositories/# Repository implementations
```

**Dependency rule:** Presentation calls domain use cases; data implementations fulfill domain repository interfaces. Domain code stays independent of Flutter, Riverpod, Dio and Odoo-specific serialization. Avoid direct API calls from UI widgets. Only add files and abstractions when a feature needs them.

Read [Architecture](docs/architecture.md), [Riverpod conventions](docs/state-management.md), and [Agent instructions](AGENTS.md).

## Testing and validation

From the repository root:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
flutter build apk --debug --flavor development --target lib/main_development.dart
```

Integration tests are manual and excluded from CI. To run the integration smoke test, connect an emulator or device:

```powershell
flutter devices
flutter test integration_test/app_test.dart --flavor development -d DEVICE_ID
```

The documented smoke test uses controlled authentication and camera overrides. It checks app flows but **does not confirm actual camera scanning, secure storage on a real device, or live Odoo behavior**. Test those separately before release.

For staging/production smoke tests, the test configuration must also match the native flavor (see the project's integration test documentation and `TEST_FLAVOR` define).

Additional validation evidence: [Task 01](docs/validation.md) and [Task 03](docs/task03-validation.md).

## Continuous integration

The fresh [Flutter Tests workflow](.github/workflows/flutter_tests.yml) runs
formatting, analysis and offline unit/widget tests on every push and pull request,
main merge queues and manual dispatch. Coverage is uploaded as an artifact.
Read [Testing strategy](docs/testing.md) for conventions, examples and commands.

Native checks use [Android](.github/workflows/android.yaml) and
[iOS](.github/workflows/ios.yaml) matrices for development, staging and production.
The [license policy](.github/workflows/license_check.yaml) remains enforced.
iOS distribution is manual from main, with protected approval and separate
archive/export runners. TestFlight does not publish the app publicly.
Read [Deployment](docs/deployment.md) for inputs, environments and release checks.

## Security and release notes

- Never commit secrets, Android keystores, Apple provisioning material or generated build outputs.
- Keep local development configuration files ignored by Git.
- Real Android distribution requires signing credentials and a protected keystore.
- iOS distribution requires an Apple Developer account, provisioning/signing and App Store Connect configuration.
- Production distribution requires a manual main-branch request and protected approval. Actual signing and iPhone testing require recorded run evidence. Firebase integrations remain future work.
- Verify permissions, network behavior and backend compatibility with real devices and a test Odoo environment before production use.

## Project documentation

- [Testing strategy and conventions](docs/testing.md)
- [Environments and logging](docs/environments-and-logging.md)
- [Authentication setup and contract](docs/authentication.md)
- [Architecture](docs/architecture.md)
- [Riverpod state management](docs/state-management.md)
- [Home scanner and barcode lookup](docs/home-scanner.md)
- [Product details](docs/product-details.md)
- [Product price update](docs/product-price-update.md)
- [Product name and tax editing](docs/product-edit.md)
- [Product creation and backend compatibility](docs/product-creation.md)
- [Splash and branding](docs/splash-branding.md)
- [Shared orange gradient and native regeneration](docs/brand-gradient.md)
- [Task 01 validation](docs/validation.md)
- [Task 03 validation](docs/task03-validation.md)
- [Agent guidance](AGENTS.md)

These links assume the corresponding documentation files exist in the repository.

## Development workflow

Create focused feature branches, open pull requests into `main`, and run formatting, analysis and relevant tests before merging. Review GitHub Actions results and keep generated files and credentials out of commits.

If Git reports **dubious ownership**, resolve the ownership/trust issue for this specific repository before retrying. Do not use a global wildcard safe-directory exception.
