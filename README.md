# Xodus for Mac

A proposed Apple-native launcher for legitimately entitled Xbox PC games, powered by a future integration with the Xodus runtime.

**Current status: public design and engineering foundation, not a working game launcher.** The SwiftUI app is an explicitly labelled, offline, fixture-only prototype. It cannot sign in, enumerate a real library, download packages, install games, or launch games. All titles, artwork, account states, compatibility claims and progress shown in the prototype are invented demonstrations.

![Original Library concept](design/previews/library.png)

## Explore the foundation

| Artifact | Purpose |
| --- | --- |
| [Product](PRODUCT.md) | Audience, scope, principles and undecided product choices |
| [Design](DESIGN.md) | Native visual direction, tokens, interaction and original mockups |
| [Requirements](docs/REQUIREMENTS.md) | Traceable requirements and measurable acceptance criteria |
| [UX flows](docs/UX-FLOWS.md) | Screens, cancellation, loading, degraded and recovery states |
| [Architecture](docs/ARCHITECTURE.md) | SwiftUI/AppKit boundary, Rust adapter and trust model |
| [Backend contract](docs/BACKEND-CONTRACT.md) | Proposed versioned JSON/JSONL management protocol |
| [Research and decisions](docs/RESEARCH.md) | Evidence, leads, uncertainties and decision register |
| [Milestones](docs/MILESTONES.md) | Release gates; prototype is not a production milestone |
| [Implementation ledger](docs/IMPLEMENTATION-LEDGER.md) | Durable v1 work IDs, actual-vs-fixture status, dependencies, evidence and blockers |
| [Editable mockups](design/README.md) | Original SVG screens, shared tokens and reproduction |

Design collaboration: [nine editable v0.2 Figma mockups](https://www.figma.com/design/5iQu716UFImHjRxJkf0t8V?node-id=3-115) and [editable FigJam UX flow](https://www.figma.com/board/3MejlFaXHkogmJ3J5k79Gw). Revised Library/Discover renders were inspected; [import status](design/README.md) records static SVG fidelity limits and superseded v0.1. These are proposed designs, not implemented APIs, exact compositor effects or a wired Figma prototype.

## Run the native fixture preview

On an Apple Silicon Mac with Swift 6 and Apple Command Line Tools:

```sh
swift run XodusFixtureChecks
swift run XodusPreview
```

The proposed deployment baseline is **macOS 14**, not a user-approved support commitment. On macOS 26+, the preview uses **real SwiftUI Liquid Glass** (`glassEffect`, `GlassEffectContainer`, glass buttons): a centered floating capsule menu and separate circular account control over original immersive imagery, with a transparent native titlebar. Older systems use explicitly availability-gated standard materials; reduced transparency uses opaque surfaces. SwiftUI/AppKit provides the modern Mac framework behavior without a UIKit rewrite or full Xcode.

**Visual revision v0.2 supersedes the unapproved flat v0.1 concepts.** SVGs describe editable layout and intended glass placement, not live compositor refraction. Native own-view exports also cannot establish backdrop/refraction fidelity; the native implementation, not an SVG blur, owns system Glass.

Choose **Library / Discover / Downloads**, search within the current scope, open a game, and use **Simulate install** or **Simulate next step**. Settings can inject empty, partial, stale, offline and cancelled-auth scenarios. Simulated jobs exist only in memory and reset on relaunch. The preview never contacts a service, invokes the runtime, opens an auth browser, or writes an installed-game registry.

```sh
swift run XodusPreview --self-check
```

The first command checks core models; `--self-check` checks presentation state without opening a window. These dependency-free check executables work with Command Line Tools, which do not include XCTest/Swift Testing on the tested Mac. [Verification](docs/VERIFICATION.md) records the actual tested environment and commands, separately from future release criteria.

`sh tools/check.sh` runs the complete foundation check sequence. GitHub Actions repeats it on a hosted Mac and checks SVG regeneration; a workflow definition is not itself a claim that hosted CI has passed.

To render only this fixture app's own native view hierarchy (not the desktop or other apps), use `swift run XodusPreview --export-preview /tmp/xodus-fixture-preview`. It exports Library, Discover and Downloads PNGs and exits. This optional explicit export writes image artifacts only; it does not write game files.

## Boundaries and licensing

The app is standalone: Heroic does not offer a proven shipping new-store plugin API. Existing Xodus runtime service IPC is **not** a launcher management protocol. A safe, stable backend, authoritative PC ownership inventory, package eligibility and exactly paired Xbox-capable runtime still need proof.

No private runtime source, credentials, real account data, proprietary game covers, Apple assets or paid design assets are included. The original app source, documentation and mockups are licensed **GPL-3.0-only**, by the user's explicit choice; see [LICENSE](LICENSE) and [licensing boundaries](docs/LICENSING.md). Third-party runtime components/assets retain their own licenses. Dependency redistribution, signing/notarization and installer distribution remain pending. This license does not grant rights to Microsoft packages or runtime components.
