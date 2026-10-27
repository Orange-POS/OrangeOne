# Riverpod state management and dependency injection

## Scope and composition

Use the installed Riverpod 3 APIs through `flutter_riverpod`. Providers are
declared manually; this foundation does not require code generation, a service
locator, a global ProviderContainer, or another state-management framework.

`bootstrap.dart` mounts the single application-root `ProviderScope` and overrides
`environmentProvider` for the selected flavor. Do not create a new scope or
container inside a page's build method. Tests create isolated scopes/containers.
Retain the native/Dart flavor validation before mounting the application.

Providers are global declarations, but their values/state belong to the scope's
container. A service cached in one container is not shared with another container.

## Implemented dependency graph

```text
bootstrap: environmentProvider override
  -> environmentLoaderProvider (shared local configuration dependency)
    -> initializationControllerProvider (feature async state)
      -> InitializationPage (renders state and dispatches retry)

App -> routerProvider -> GoRouter (disposed with its provider)
```

The configuration loader is a typed function (`EnvironmentLoader`) injected by a
normal Provider. Its production implementation returns the configured local
environment asynchronously, without IO, artificial delays or service credentials.
It deliberately uses no extra service class where a single operation suffices.
Tests replace this dependency with controlled futures or failures. This is an
initialization example, not an Odoo/Firebase integration or session check.

`InitializationController` owns initialization and retry decisions. Riverpod
converts its build Future into `AsyncLoading`, `AsyncData` or `AsyncError`. The
page watches that state and renders it; it neither constructs dependencies nor
performs service calls. Real business rules belong in domain use cases when those
features are implemented, rather than in widgets or provider constructors.

## Provider selection and naming

| Purpose | API | Naming convention |
| --- | --- | --- |
| Immutable configuration, service or repository injection | `Provider<T>` | `environmentProvider`, `<service>Provider`, `<feature>RepositoryProvider` |
| Read-only asynchronous query | `FutureProvider<T>` | `<feature><query>Provider` |
| Read-only asynchronous subscription | `StreamProvider<T>` | `<feature><subscription>Provider` |
| Mutable synchronous feature state | `NotifierProvider<Controller, State>` | `<feature>ControllerProvider` and `<Feature>Controller` |
| Async feature state with actions | `AsyncNotifierProvider<Controller, State>` | `<feature>ControllerProvider` and `<Feature>Controller` |

Files use snake_case; provider variables use lowerCamelCase with `Provider` as
the suffix. Supply a matching `name:` for manually declared providers to aid
diagnostics. Existing `environmentProvider` and `routerProvider` names are retained.
Do not introduce legacy StateProvider/StateNotifierProvider or mix Riverpod 2
auto-dispose notifier classes with Riverpod 3 APIs.

Keep feature controllers and dependency wiring in `presentation/providers/`.
Keep shared configuration/service providers beside their infrastructure in core.
Keep app routing/composition in app. Domain code must not import Riverpod.
Inject ordinary constructor arguments or callbacks into services; do not pass Ref
or WidgetRef into domain entities, use cases or service implementations.

Use `ref.watch` for dependencies that should rebuild when changed. Use `ref.read`
inside UI event callbacks to invoke notifier actions. Use `ref.listen` for an
explicit one-time UI effect, such as a message, not for deriving ordinary state.
Store immutable values in state and expose changes through controller methods.
Keep purely visual focus, animation and text-editing controllers in widget state
unless a real feature requirement needs shared ownership.

## Async state and concurrent operations

- Render loading, data and safe error states explicitly. Collections represent
  empty results as successful empty data; initialization returns an environment,
  so an empty configuration state is not applicable here.
- The initialization page shows loading on refresh/reload too; it never reports
  initialization success before the loader completes.
- The controller refuses retry while loading. `ref.invalidateSelf()` starts a new
  read; Riverpod handles state transitions and ignores obsolete build results.
  Avoid duplicating the same async result in several mutable providers.
- Initialization disables Riverpod 3 automatic retry via its `retry` callback;
  failures stay visible until the user requests another attempt. Decide retry
  policy explicitly for future providers. Never automatically retry writes
  without a confirmed idempotency policy.
- Do not put async work in widget build methods. Prefer watched build Futures for
  declarative reads. For future imperative async actions, guard concurrent calls,
  use `AsyncValue.guard` where appropriate, check `ref.mounted` after awaiting,
  and define stale-result behavior when dependencies can change mid-operation.
- Keep exceptions/stack traces out of UI text and sensitive telemetry. This
  diagnostic page displays a fixed safe message; typed domain failures and their
  mapping should be added with the feature that defines them.

## Lifecycle and ownership

`environmentProvider`, `environmentLoaderProvider` and `routerProvider` are lazy,
container-lived dependencies. They are shared within that root container and are
released when it is disposed or their dependencies are invalidated. The router's
existing `ref.onDispose(router.dispose)` closes its owned resource.

Feature state defaults to `.autoDispose`; initialization follows this rule. With
no listeners, Riverpod can release it. Watching it again initializes fresh state.
Do not add keepAlive merely to hide repeated loads. Document an actual caching or
application-lifetime requirement before retaining feature state. Parameterized
providers should use auto-dispose unless a bounded cache policy is defined.

Register cancellation/cleanup with `ref.onDispose` when creating a client,
subscription, timer or cancelable request. The provider that creates a resource
owns its cleanup; consumers must not close a shared dependency. Do not mutate
other providers from cleanup. Ignoring an obsolete Future result does not cancel
underlying IO: future network integrations must attach real cancellation where
supported. The current local loader owns no resource requiring cancellation.

## Testing with overrides

Use a fresh `ProviderContainer.test()` for each provider test; Riverpod disposes
it at test completion. Keep auto-dispose providers listened to while asserting
state, then close the listener to exercise disposal. Widget tests use a root
ProviderScope with overrides. Do not share containers between tests.

Override service dependencies rather than mocking the controller implementation:

```dart
final pending = Completer<AppEnvironment>();
final container = ProviderContainer.test(
  overrides: [
    environmentLoaderProvider.overrideWithValue(() => pending.future),
  ],
);
final subscription = container.listen(
  initializationControllerProvider,
  (previous, next) {},
);
expect(subscription.read().isLoading, isTrue);
pending.complete(AppEnvironment.staging);
expect(
  await container.read(initializationControllerProvider.future),
  AppEnvironment.staging,
);
```

Use Completers and `container.pump()` rather than arbitrary delays. A widget test
must not call `pumpAndSettle()` while deliberately leaving a loading spinner's
Future incomplete; complete the future or use bounded pumps first.

Current tests cover environment injection and container isolation, loading/data,
failure/retry, duplicate-action prevention, dependency replacement with an obsolete
pending result, auto-disposal with a pending result, and safe page error/retry UI.
All tests use local dependencies, without a camera, backend or Firebase.

## Authentication extension (Task 04)

Task 04 extends these conventions with container-lived `sessionControllerProvider`
so authentication survives route changes. `authRepositoryProvider` injects the
shared Mobile API client, secure store, API configuration and clock. Session expiry
timers are disposed, login is single-flight, and logout invalidates pending results.
Network/token-check failures remain explicit; challenge validation is never retried
automatically. See [authentication](authentication.md) for the concrete contract,
restore/expiry policy, cancellation and serialized secure-storage operations.

## Product lookup extension (Task 05)

Product providers follow the same manual Riverpod 3 conventions. The app binds
the feature's repository contract to the current secure session at bootstrap;
cross-feature wiring lives in `app/providers/product_dependencies.dart`.
`productLookupControllerProvider` is auto-disposed and uses explicit idle,
loading, found/not-found and safe failure states. It suppresses duplicate work,
disables automatic retry, and ignores disposed or obsolete results. Its data
source's CancelToken is disposed with its repository. See [Home scanner](home-scanner.md)
for the contract, platform format policy and testing overrides.

## Product details extension (Task 06)

Task 06 adds the auto-dispose `productDetailsControllerProvider(barcode)` family
and `ProductDetailsController`. Its repository contract is independently injected
by app composition using the current session, shared client and a cancellation
token. No Home data/presentation dependency is imported. Initial loads, explicit
refresh and confirmed writes have no automatic retries. Generation and mounted
checks prevent obsolete refresh/write completions replacing new session state.
Tests override `productDetailsRepositoryProvider` in fresh containers and listen
to the family while testing it. See [Product details](product-details.md).

## Product price update extension (Task 07)

Task 07 adds auto-dispose `priceUpdateControllerProvider(barcode)` /
`PriceUpdateController` with a `PriceUpdateState` and explicit editing, checking,
saving, saved and uncertain phases. It reuses the independently injected Products
repository and domain CHF/price operations. Confirmation snapshots are checked
against the current draft, followed by server permission/identity/price checks.
No write is automatically retried; uncertain outcomes require a safe read first.
Successful acknowledgments invalidate the details controller. Generation and
mounted checks protect asynchronous actions. See [Price update](product-price-update.md).

## References

Task 08 adds the auto-dispose `productEditControllerProvider(barcode)` family with
independent editing, checking, saving, saved and uncertain phases. It shares the
Products repository, validates names in the domain and loads company tax options
through the repository. Nullable draft tax IDs mean preserve existing assignments;
an empty list is an explicit removal. See [Product editing](product-edit.md).

- [Riverpod provider testing](https://riverpod.dev/docs/how_to/testing)
- [Riverpod automatic retry](https://riverpod.dev/docs/concepts2/retry)
- [Riverpod 3 API and lifecycle changes](https://riverpod.dev/docs/whats_new)



