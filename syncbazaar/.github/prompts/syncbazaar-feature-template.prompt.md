---
name: "SyncBazaar Feature Template"
description: "Scaffold or implement a SyncBazaar feature with consistent screen, bloc, models, repository, and role-aware UX patterns. Use for new feature slices or structured refactors."
argument-hint: "Feature name, target screens, roles impacted, and whether to include models/repository/tests"
agent: "SyncBazaar Flutter Developer"
---
Build a production-ready SyncBazaar feature slice using existing project architecture and design rules.

Input:
- Feature name and goal: {{input}}

Execution requirements:
1. Identify existing related files and reuse shared widgets/theme tokens first.
2. Implement or update screen files under lib/ui/screens/<feature>/.
3. Add or update bloc under lib/bloc/<feature>/ with clear states/events.
4. Add or update models/repository contracts if required by feature scope.
5. Keep role-aware behavior explicit for Admin, Owner, Employee.
6. Keep UI compliant with dashboard visual language and tablet landscape workflow.
7. Keep offline-first boundaries clear (local-first, sync-ready interfaces).

Output requirements:
- Apply edits directly in files.
- Provide short change summary with file list.
- Call out assumptions and TODO hooks for future backend/sync/AI integration.
