# AGENTS.md — hclq Coding Guidelines

## Project Overview

**hclq** is a CLI tool for querying and modifying HCL (HashiCorp Configuration Language) files,
analogous to `jq` for JSON. It parses HCL v1 AST directly and supports dot-path queries,
wildcards, regex matching, and list indexing.

- Module: `github.com/pycabbage/hclq`
- Go: 1.24 (see `go.mod`)
- Default branch: `develop` (`master` is upstream-sync only)

---

## Build, Test & Lint Commands

### Build

```bash
make build              # → dist/hclq (with version ldflags)
make clean              # remove dist/
make install            # go install to $GOPATH/bin
```

Direct build (no Makefile):
```bash
go build -ldflags="-s -w -X github.com/pycabbage/hclq/cmd.version=$(git describe --always --dirty)" -o dist/hclq .
```

### Test

Tests are **integration tests** that invoke the compiled binary. `make test` always rebuilds first.

```bash
make test                                                        # build + run all tests
HCLQ_BIN=./dist/hclq go test -v ./...                          # run all tests (binary must exist)
HCLQ_BIN=./dist/hclq go test -v -run TestGet ./cmd/            # run all TestGet subtests
HCLQ_BIN=./dist/hclq go test -v -run 'TestGet/get_a$' ./cmd/  # run a single subtest by name
```

Subtest names are derived from the args joined with spaces (e.g. `"get -r a[0]"`).
Special characters like `[]` must be escaped in `-run` patterns: `TestGet/get_a\[\]`.

### Lint

```bash
golangci-lint run       # uses default config (no .golangci.yml present)
go vet ./...            # built-in static analysis
```

### GoReleaser (release builds)

```bash
goreleaser build --snapshot --clean   # local snapshot for all platforms
goreleaser check                      # validate .goreleaser.yml
```

---

## Architecture

```
main.go              → cmd.Execute() (3-line entry point)
cmd/root.go          → cobra RootCmd, --in / --out flags, version (injected by ldflags)
cmd/get.go           → "get" and "get keys" subcommands
cmd/set.go           → "set", "set append", "set prepend", "set replace" subcommands
cmd/common.go        → shared I/O helpers (getInputReader, getOutput)
config/config.go     → global flag state (UseRawOutput, InputFile, OutputFile, …)
hclq/query.go        → HclDocument, Query engine, AST walker
hclq/get.go          → Get, GetKeys, GetAsInt, GetAsList, … typed accessors
hclq/set.go          → Set (dispatches listAction / valueAction callbacks)
hclq/utils.go        → JSON → HCL AST conversion (HclFromJSON, HclListFromJSON)
query/breadcrumbs.go → query DSL parser; Crumb / IndexedCrumb interfaces
```

---

## Code Style

### Formatting & Imports

- Format with **`gofmt`** (enforced). No width limit beyond standard Go convention.
- Use **`goimports`** for import management. Two groups separated by a blank line:
  1. Standard library
  2. External and internal packages (may be combined into one block)
- Use import aliases only when there would be a name conflict (e.g. `testifyAssert`, `jsonParser`).

### Naming

| Kind | Convention | Examples |
|---|---|---|
| Exported types | PascalCase | `HclDocument`, `Breadcrumbs`, `Result` |
| Exported functions / methods | PascalCase | `FromReader`, `GetAsInt`, `HclFromJSON` |
| Unexported functions | camelCase | `walk`, `performSet`, `getTokenType` |
| Receiver names | Short (1–3 chars), type initial | `doc`, `k`, `l`, `r`, `w` |
| Cobra command vars | PascalCase + `Cmd` suffix | `RootCmd`, `GetCmd`, `SetCmd` |
| Config package vars | PascalCase | `UseRawOutput`, `InputFile` |
| Local variables | camelCase | `newValue`, `listNode`, `isMatch` |

### Error Handling

- Use **`fmt.Errorf("context: %s", err.Error())`** for errors with dynamic content.
- Use **`errors.New("message")`** for static, context-free error messages.
- **Do not use `%w`** for error wrapping — the codebase does not use `errors.Is`/`errors.As`.
- **Do not define custom error types** or sentinel errors.
- Always check errors immediately and return them inline — no deferred error handling.
- `panic` is reserved for explicitly unimplemented code paths only (add a `// TODO` comment).
- Do not silently discard errors (`_, err = f()` without handling is a bug).

### Comments & Documentation

- All exported symbols **must** have a doc comment starting with the symbol name:
  ```go
  // HclDocument represents an HCL document in memory.
  type HclDocument struct { … }

  // FromReader creates a new document from an io.Reader.
  func FromReader(reader io.Reader) (*HclDocument, error) { … }
  ```
- Unexported functions do not require doc comments but should have them if non-obvious.
- Mark unfinished work with `// TODO: description`.

### CLI (Cobra)

- All commands use **`RunE`** (not `Run`) so errors propagate to cobra's error handler.
- Validate argument counts declaratively with `cobra.ExactArgs(N)`.
- Register subcommands in `init()` using `ParentCmd.AddCommand(ChildCmd)`.
- Global I/O flags (`--in`, `--out`) live on `RootCmd.PersistentFlags()`.
- Subcommand-specific flags use `cmd.PersistentFlags()` (if cascading) or `cmd.Flags()`.
- Version string is injected at link time via ldflags `-X …cmd.version=…`; do not hardcode it.

### Configuration / Global State

- All mutable CLI state lives in the **`config` package** as exported `var` declarations.
- Cobra binds flags directly to these vars via `StringVarP` / `BoolVarP` / `IntVarP` in `init()`.
- Do not pass config values as function parameters — read from `config.*` directly in `RunE`.
- Do not add new global state outside `config/config.go`.

### Testing

- Tests are **integration tests**: they compile the binary and invoke it via `exec.Command`.
- The binary path comes from the `HCLQ_BIN` environment variable (set by `make test`).
- Use **table-driven tests** (`var tests = []struct{…}{…}`) for all command-level tests.
- Feed input over stdin with `cmd.StdinPipe()` and a goroutine.
- Assert errors via `(*exec.ExitError).Stderr` with `assert.Contains(stderr, expectedSubstring)`.
- Strip the trailing newline from stdout before asserting: `strings.TrimRight(output, "\n")`.
- Name subtests with `strings.Join(args, " ")` so `-run` patterns match the CLI invocation.
- Import `testify/assert` with an alias (`testifyAssert`) and instantiate per-subtest with `.New(t)`.

---

## Known Issues / TODOs

- `HclLiteralFromJSON` in `hclq/utils.go` returns `(nil, nil)` on error — this is a bug.
- `set replace` on lists is not implemented (panics with a TODO message).
- HCL v1 (`github.com/hashicorp/hcl`) is unmaintained; HCL v2 migration is a future concern.
- The `walk` function uses `fmt.Println` as a debug fallback for unhandled AST node types.
