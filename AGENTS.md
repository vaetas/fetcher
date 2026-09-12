# AGENTS.md

Guidance for AI coding agents working in this repository.

This repository builds a **native macOS-only developer application**. Native macOS design, behavior, accessibility, and use of Apple frameworks are product requirements, not optional polish.

A deeper `AGENTS.md` may add or override rules for its subtree.

---

## 1. Product Contract

Build a focused local API client for macOS.

Current protocol:

- REST over HTTP/HTTPS.

Future protocols:

- GraphQL.
- gRPC.

The architecture must leave clean extension points for those protocols without implementing them speculatively.

The application is:

- macOS-only;
- native;
- local-first;
- account-free;
- cloud-independent;
- keyboard-friendly;
- accessible.

Do not optimize for Windows, Linux, web, iOS, iPadOS, or cross-platform compatibility.

If a product specification or ADR exists, read the relevant document before changing product behavior. This file governs engineering and design principles; the product specification governs feature requirements.

---

## 2. Platform Baseline

Target:

- **macOS 27+**
- current Xcode toolchain for that target
- modern Swift
- modern Swift concurrency

Prefer APIs available on the deployment target instead of adding compatibility code for older macOS versions.

### Default Apple stack

Prefer these frameworks:

- **SwiftUI** — application shell and most UI.
- **AppKit** — macOS capabilities or advanced controls where SwiftUI is insufficient.
- **Foundation** — networking, URLs, parsing, formatting, dates.
- **SwiftData** — ordinary local application data.
- **Security / Keychain Services** — credentials and secrets.
- **OSLog** — diagnostics.
- **Swift Testing** — tests.

### Dependency policy

Default to Apple frameworks.

Before adding a third-party package, verify that:

1. Apple frameworks do not adequately solve the problem.
2. The package removes substantial complexity or risk.
3. It preserves native macOS behavior.
4. It is actively maintained.
5. It does not force a cross-platform architecture onto the app.

Do not add a dependency merely to save a small amount of Swift code.

### Prohibited foundations

Do not introduce:

- Electron;
- Tauri;
- Flutter;
- React Native;
- Mac Catalyst;
- HTML/CSS/JavaScript as the primary UI;
- an embedded web app as the application shell;
- a local web server for UI;
- cross-platform UI abstraction frameworks.

`WKWebView` is acceptable only for a feature that inherently needs web content.

---

## 3. Native macOS First

When multiple implementations are reasonable, prefer the one that behaves most like a first-class Mac application.

Think in terms of:

- windows;
- sidebars;
- inspectors;
- toolbars;
- menus;
- context menus;
- focus and selection;
- keyboard commands;
- native text editing;
- copy/paste;
- undo/redo;
- drag and drop;
- system settings;
- native file dialogs;
- resizable desktop layouts.

Do not design a mobile UI and enlarge it for desktop.

Do not copy web-dashboard conventions into SwiftUI by default.

---

## 4. Apple HIG Is the Design Authority

For design questions, current Apple Human Interface Guidelines outrank generic web/mobile conventions.

Primary references:

- Human Interface Guidelines  
  https://developer.apple.com/design/human-interface-guidelines/
- Materials / Liquid Glass  
  https://developer.apple.com/design/human-interface-guidelines/materials
- Toolbars  
  https://developer.apple.com/design/human-interface-guidelines/toolbars
- Sidebars  
  https://developer.apple.com/design/human-interface-guidelines/sidebars
- Menus  
  https://developer.apple.com/design/human-interface-guidelines/menus
- Accessibility  
  https://developer.apple.com/design/human-interface-guidelines/accessibility

For unfamiliar or newly introduced APIs, verify current Apple documentation before implementing.

Do not blindly reuse old SwiftUI/AppKit patterns when modern APIs exist.

---

## 5. Liquid Glass

Use **real system Liquid Glass**.

Prefer standard SwiftUI/AppKit containers and controls so macOS provides the correct current appearance automatically.

Liquid Glass belongs primarily to the functional/navigation layer:

- window chrome;
- toolbars;
- sidebars;
- inspectors;
- menus;
- popovers;
- sheets;
- transient controls.

Do **not** use Liquid Glass as generic decoration.

Never:

- put every content section in a glass card;
- make request/response editors translucent;
- stack custom blur layers;
- simulate Liquid Glass with gradients and opacity;
- create a bespoke glass design system;
- apply `glassEffect` simply to make content look modern.

Use custom glass effects only when a system component cannot express the required interaction.

Content should remain clear, dense, and readable.

---

## 6. Preferred macOS UI Primitives

Use native structures first:

- `NavigationSplitView`
- `List`
- `Table`
- `Form`
- `Inspector`
- `.toolbar`
- `.searchable`
- `.commands`
- `Menu`
- context menus
- `Settings`
- standard sheets
- standard popovers
- standard alerts

For the main workspace, prefer:

1. leading project/request navigation;
2. central request/response workspace;
3. optional trailing inspector for contextual metadata/settings.

### Sidebar

Use the sidebar for navigation and hierarchy.

Good sidebar content:

- projects;
- saved requests;
- favorites/recent items if introduced.

Use native selection behavior.

Avoid deeply nested trees. A new conceptual level may deserve another column or detail view instead.

### Toolbar

Use the toolbar for frequent actions and navigation.

Likely toolbar actions:

- send/cancel request;
- environment selection;
- sidebar visibility;
- inspector visibility;
- search.

Do not overcrowd it.

Secondary actions belong in menus, context menus, inspectors, or settings.

### Inspector

Use a native inspector for secondary properties of the current selection.

Do not build a permanent custom right-hand panel when the system inspector model fits.

### Settings

Use the native macOS Settings scene.

---

## 7. Avoid Web-App Visual Language

Avoid these patterns unless a concrete product requirement justifies them:

- pages composed from rounded cards;
- arbitrary card grids;
- huge marketing-style titles;
- decorative gradients;
- excessive shadows;
- pill buttons for ordinary actions;
- floating action buttons;
- hamburger menus;
- mobile tab bars;
- browser-style custom dropdowns;
- third-party icon sets for standard actions;
- Tailwind/shadcn-style spacing and radius systems copied into SwiftUI;
- custom replicas of standard controls.

Do not create custom versions of:

- toggles;
- checkboxes;
- search fields;
- pickers;
- segmented controls;
- menus;

when the standard component is suitable.

Do not create a generic `Card` component and use it as the default container for UI.

---

## 8. SwiftUI vs AppKit

### Prefer SwiftUI for

- scenes and windows;
- navigation;
- lists and tables;
- forms;
- toolbars;
- inspectors;
- settings;
- sheets and popovers;
- menus and commands;
- standard controls;
- state-driven presentation.

### Use AppKit when it materially improves the Mac experience

Examples:

- `NSTextView` / TextKit for advanced editors;
- window behavior not exposed cleanly in SwiftUI;
- low-level focus or keyboard needs;
- advanced pasteboard handling;
- specialized native controls;
- macOS APIs only available through AppKit.

Do not use AppKit simply because an older solution is familiar.

### AppKit bridge rule

Keep `NSViewRepresentable`, coordinators, delegates, and window controllers narrow.

They translate platform behavior into app/domain state.

Do not put business logic, networking, persistence, or request construction inside AppKit bridges.

---

## 9. Native Text Editing

This is a developer tool. Text editing quality matters.

Use:

- SwiftUI text controls for simple fields;
- `NSTextView` / TextKit when body/code editing needs richer behavior.

Preserve native behavior:

- selection;
- copy/paste;
- undo/redo;
- find;
- keyboard navigation;
- accessibility;
- text services;
- cursor behavior;
- native scrolling.

Use system monospaced typography for:

- HTTP bodies;
- headers;
- raw requests/responses;
- code-like content.

Do not embed Monaco, CodeMirror, or another browser editor for the primary editor without an explicit product decision.

---

## 10. Menus, Commands, and Keyboard Navigation

Important actions must be modeled as commands, not only as button closures.

Prefer SwiftUI:

- `Commands`
- `CommandMenu`
- `CommandGroup`
- `keyboardShortcut`

The same conceptual action should be reusable from:

- toolbar;
- main menu;
- context menu;
- keyboard shortcut.

Do not scatter raw keyboard event monitors through view code when a command can express the behavior.

When adding a shortcut:

1. Prefer conventional macOS bindings.
2. Expose the action in a menu when appropriate.
3. Respect current focus and selection.
4. Avoid conflicts with standard text editing shortcuts.
5. Keep labels/accessibility descriptions meaningful.

The architecture should make it easy to add shortcuts later for:

- new project;
- new request;
- send;
- cancel;
- duplicate;
- focus URL;
- search;
- toggle sidebar;
- toggle inspector;
- change request editor section;
- change response section.

---

## 11. Typography, Icons, and Color

Use system typography.

Use:

- standard system font for general UI;
- system monospaced font for code and protocol data.

Prefer SF Symbols for interface icons.

Do not add an icon package for ordinary Mac actions.

Use color sparingly and semantically.

Do not encode meaning by color alone.

Do not remove focus rings for visual cleanliness.

---

## 12. Accessibility

Accessibility is required.

Prefer system controls because they inherit useful semantics.

Evaluate new UI for:

- VoiceOver;
- Full Keyboard Access;
- focus order;
- Increase Contrast;
- Reduce Transparency;
- Reduce Motion when animations exist.

Icon-only controls need meaningful accessibility labels/help.

Custom AppKit controls need appropriate accessibility roles and values.

Hover must not be the only way to discover or operate a feature.

---

## 13. Windows and Desktop Layout

Respect standard Mac window behavior.

Unless the product specification states otherwise:

- windows are resizable;
- views adapt to available width/height;
- sidebars and inspectors have sensible minimum/default widths;
- important content is not designed around one fixed window size.

Avoid:

- fixed-size application layouts;
- custom title bars;
- hiding standard window controls;
- unusual window chrome.

Use native sheets for window-scoped modal work.

Use alerts only when interruption or explicit confirmation is justified.

---

## 14. Local-Only and Privacy

The app is local-only by default.

Do not add:

- sign-in;
- accounts;
- analytics;
- telemetry;
- advertising;
- cloud synchronization;
- remote configuration;
- remote project storage.

The app should make network calls only for behavior explicitly required by the product—primarily requests the user chooses to send.

Do not silently contact external services.

### Secrets

Credentials belong in Keychain.

Examples:

- bearer tokens;
- API keys;
- passwords;
- client secrets.

Do not store secrets as ordinary SwiftData fields or plaintext files.

Never log secrets.

Never include secrets in diagnostics.

---

## 15. HTTP Networking

Use Foundation `URLSession` as the REST transport.

Useful native primitives include:

- `URLRequest`
- `URLSession`
- `HTTPURLResponse`
- `URLComponents`
- `URLQueryItem`

Do not add Alamofire merely to wrap basic `URLSession` behavior.

Transport code does not belong in SwiftUI views.

Views express intent:

- edit;
- send;
- cancel.

A networking/executor layer performs transport work.

---

## 16. Protocol Extensibility

Do not make shared app architecture synonymous with REST.

Use an explicit protocol boundary, for example conceptually:

```text
Project
└── RequestDefinition
    └── protocol-specific configuration

RequestExecutor
├── RESTRequestExecutor
├── GraphQLRequestExecutor   // future
└── GRPCRequestExecutor      // future
```

Shared project concepts may include:

- name;
- base endpoint;
- variables;
- common headers;
- credential references.

Protocol-specific request state should remain protocol-specific.

Do not distort GraphQL or gRPC into REST-shaped models just for reuse.

Do not implement future protocols until requested.

Design extension points, not speculative functionality.

---

## 17. Architecture

Prefer simple feature-oriented organization.

A reasonable shape:

```text
App/
Domain/
Features/
    Projects/
    Requests/
    Response/
    Settings/
Networking/
    REST/
Persistence/
Security/
UI/
    Components/
    Editors/
```

Adapt to the actual repository rather than reorganizing code only to match this example.

### Views stay thin

Views may:

- render state;
- bind editable data;
- dispatch user actions;
- own small transient presentation state.

Views should not:

- perform direct `URLSession` work;
- implement Keychain access;
- contain persistence internals;
- synchronously process large response bodies;
- build complex protocol requests inline.

### Avoid architecture ceremony

Do not create a protocol/interface for every type.

Add abstraction for meaningful boundaries such as:

- transport/protocol implementations;
- external side effects;
- testable system boundaries;
- platform-specific adapters.

Avoid layers that merely forward calls.

Avoid vague types such as:

- `Helper`;
- `Utils`;
- `CommonManager`.

---

## 18. State and Concurrency

Prefer modern Observation patterns appropriate to the target SDK.

Keep state ownership explicit.

Avoid giant global observable objects.

Avoid singleton application state by default.

Use structured concurrency:

- `async` / `await`;
- cancellation;
- actors when shared mutable state requires isolation;
- `@MainActor` for UI-facing state.

Do not:

- block the main actor with parsing or I/O;
- create unnecessary detached tasks;
- manually dispatch to queues when structured concurrency suffices.

Cancelling a request should cancel underlying network work where possible.

---

## 19. HTTP/Developer-Tool Error Quality

Errors must be useful to someone debugging an API.

Preserve distinctions such as:

- malformed URL;
- DNS failure;
- connection failure;
- timeout;
- TLS/certificate failure;
- cancellation;
- invalid request construction;
- HTTP status response.

Do not collapse everything into “Something went wrong.”

Do not expose only an opaque Swift error when a concise contextual message can be shown.

Detailed technical information may be available in a secondary detail/inspector area.

---

## 20. Performance

The app should feel immediate.

Be careful with:

- large response bodies;
- JSON formatting;
- syntax highlighting;
- body editors;
- long request lists;
- persistence writes.

Do not parse, format, or highlight potentially large payloads synchronously on the main actor.

Prefer asynchronous/lazy work when payload size can be significant.

Do not prematurely optimize ordinary UI.

---

## 21. Agent Workflow

Before changing code:

1. Read this file.
2. Check for nested `AGENTS.md` files.
3. Read relevant existing implementation.
4. Read the relevant product spec/ADR if behavior changes.
5. Search for an existing component/pattern before adding a new one.
6. Determine whether SwiftUI/macOS already provides the interaction.
7. Verify current Apple docs for uncertain or new APIs.

When implementing UI, follow this order:

1. standard SwiftUI;
2. narrowly scoped AppKit bridge;
3. custom native control/drawing only when necessary.

Do not begin by adding a dependency.

Do not perform unrelated refactors.

Do not add speculative features.

---

## 22. Build and Verification

After meaningful changes:

1. Build the affected macOS target.
2. Run relevant tests.
3. Fix warnings introduced by the change.
4. Verify affected UI at multiple reasonable window sizes.
5. Check keyboard focus for edited workflows.
6. Check light/dark appearance when styling changes.
7. Check accessibility for custom/icon-only controls.
8. Confirm privacy/local-only behavior was not changed unintentionally.

Use repository-provided scripts when available.

Otherwise use the appropriate `xcodebuild` scheme and macOS destination.

Never claim a build/test succeeded unless it was actually run successfully.

If the current environment cannot execute Xcode/macOS builds, state that limitation in the final summary and perform all available static/portable checks.

---

## 23. Native UI Review Gate

Before declaring UI work complete, verify:

### Structure

- Is this a recognizable Mac interaction?
- Is the information density appropriate for desktop?
- Is navigation expressed using standard macOS structures?

### Components

- Can any custom control be replaced by a system control?
- Are toolbar/sidebar/inspector/menu APIs used appropriately?
- Is Liquid Glass system-provided and restrained?

### Input

- Does text editing behave like macOS?
- Can keyboard users operate the feature?
- Are commands represented in menus where expected?

### Accessibility

- Are semantics meaningful?
- Does the UI tolerate Reduce Transparency / Increase Contrast?
- Is meaning preserved without color?

### Architecture

- Is networking outside views?
- Is AppKit bridging narrow?
- Did the change introduce unnecessary cross-platform abstractions?

If several answers are “no,” revise the design.

---

## 24. Patterns Requiring Explicit Justification

Treat these as code-review warnings:

- custom navigation instead of native split navigation;
- custom title bar/window chrome;
- hand-built glass/blur backgrounds;
- generic cards throughout the UI;
- custom dropdown instead of `Picker`/`Menu`;
- custom toggle/checkbox/search field;
- embedded browser code editor;
- third-party networking wrapper around simple `URLSession`;
- third-party icon package;
- global singleton state;
- URLSession calls directly from views;
- plaintext secret storage;
- fixed-size layouts;
- mouse-only features;
- icon-only controls without accessible labels;
- raw keyboard interception where Commands suffice;
- cross-platform compatibility code in a macOS-only target;
- speculative GraphQL/gRPC implementation;
- architecture layers with no real responsibility.

These are not impossible choices, but they require a concrete technical/product reason.

---

## 25. Code Quality

Prefer clear Swift over clever Swift.

Keep types focused.

Avoid enormous views and manager objects.

Use comments for:

- non-obvious platform constraints;
- protocol invariants;
- security decisions;
- surprising workarounds.

Do not add comments that merely narrate obvious code.

Do not force unwrap unless an invariant is genuinely guaranteed and clear.

---

## 26. Instruction Priority

When instructions conflict, follow this order:

1. direct user/task requirements;
2. deeper scoped `AGENTS.md`;
3. this root `AGENTS.md`;
4. product specification / ADRs;
5. established code conventions;
6. generic assumptions.

Do not preserve a legacy pattern when it violates an explicit current product constraint.

---

## 27. Final Checklist

Before finishing a patch:

- [ ] macOS-only direction is preserved.
- [ ] Apple frameworks were preferred.
- [ ] No unjustified dependency was added.
- [ ] Native controls/layouts were used where practical.
- [ ] Liquid Glass is genuine and restrained.
- [ ] UI does not look like a transplanted web/mobile interface.
- [ ] Keyboard/focus behavior was considered.
- [ ] Accessibility was considered.
- [ ] Networking is outside views.
- [ ] Secrets remain secure.
- [ ] Local-only/privacy behavior is preserved.
- [ ] REST design leaves clean GraphQL/gRPC extension points.
- [ ] Relevant build/tests were run or the inability to run them is stated.
- [ ] No unrelated refactor or speculative feature was introduced.

If these conditions are not met, the work is not complete.
