# Create PR Settings

When the user says `do createPR.md`, create a GitHub pull request using these settings.

## Repository

- Repository: `ndq3004/gitops-dotnet-api`
- Base branch: `main`
- Head branch: current branch unless a different branch is explicitly requested
- PR mode: draft by default
- Maintainer edits: enabled

## Before Creating

1. Check the current branch:

   ```powershell
   git branch --show-current
   ```

2. Check local changes:

   ```powershell
   git status --short --branch
   ```

3. Compare the branch with `main`:

   ```powershell
   git diff --stat origin/main...HEAD
   git diff --name-status origin/main...HEAD
   ```

4. Do not include unrelated untracked or modified files unless the user explicitly asks.

## PR Title

Use this format:

```text
[codex] short summary of the branch changes
```

## PR Body

Use this structure:

```markdown
## Summary

- What changed.
- What files or workflows were added or updated.
- Any intentional temporary state, such as disabled/commented jobs.

## Why

Explain the reason for the change.

## Validation

- List checks run.
- If checks were not run, explain why.
```

## Command

Prefer the GitHub connector when available. If it cannot create the PR, use:

```powershell
gh pr create --repo ndq3004/gitops-dotnet-api --base main --head <branch> --draft --title "<title>" --body "<body>"
```
