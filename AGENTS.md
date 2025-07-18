# Agent Guidelines for Flamingo

## Build/Test Commands
- Frontend: `cd frontend && npm run dev` (development), `npm run build` (production), `npm run lint` (linting)
- Backend: `cd backend && go run main.go` (development), `go build` (production)
- No test commands found - check with user if tests exist

## Code Style

### Frontend (SolidJS + TypeScript)
- Use SolidJS with TypeScript (.tsx files)
- Prettier config: 4-space tabs, single quotes, trailing commas (ES5)
- ESLint: Standard rules, unused vars allowed if uppercase/underscore pattern
- Imports: External libraries first, then relative imports
- Components: PascalCase, export as named exports
- Constants: UPPER_SNAKE_CASE (e.g., `CANVAS_WIDTH`, `MIN_PLAYERS`)
- Use `class` instead of `className` for SolidJS

### Backend (Go)
- Standard Go formatting with `gofmt`
- Package structure: `backend/` with subpackages (api, game, messages, room, words)
- Imports: Standard library first, then external, then local packages
- Error handling: Always check and handle errors explicitly
- Naming: camelCase for private, PascalCase for public
- Use goroutines and channels for concurrency (see game event handling)

## Architecture
- Frontend: SolidJS with Vite, TailwindCSS for styling
- Backend: Go with Gorilla WebSocket and Mux router
- Real-time communication via WebSocket connections