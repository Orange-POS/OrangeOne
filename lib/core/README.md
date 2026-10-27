# Core infrastructure

Application-wide, non-UI infrastructure belongs here. The existing `config/`
directory supplies environment configuration and its Riverpod provider.

Task 04 adds `network/` (Dio and the Mobile API v2 REST client), `storage/` (SecretStore and secure platform
adapter), `errors/` (safe typed failures) and `formatting/` (strict UTC timestamps).
Providers own shared dependency lifetimes; credentials never enter a request logger.

Add network clients, storage adapters, error handling or other infrastructure only
when an implemented task needs them. Do not create speculative service classes.
Keep feature-specific data sources, mappings and business rules inside their feature.

Core must not import `app/`, `features/` or `shared/`. Reusable widgets belong in
`shared/`; app startup and routing belong in `app/` and `bootstrap.dart`.
See [architecture conventions](../../docs/architecture.md).
