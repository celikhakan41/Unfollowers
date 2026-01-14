# Unfollowers – Codex Working Rules

## Non-negotiables
1. Never claim "it works" without proof.
2. After every change run:
   - `make build`
   - and if behavior/test related: `make test`
3. Paste the xcbeautify output (or summarize + include the first error line + file:line).
4. Keep changes small and atomic.
5. If `make test` creates clone simulators, do not manually close them; prefer fixing destination/UDID.

## Default commands
- Build: `make build`
- Test:  `make test`
- Run:   `make`
- List simulators: `make list-sims`