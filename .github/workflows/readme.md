# GitHub Actions flow

Muc tieu don gian:

- Tao hoac cap nhat PR vao `main` -> chay `PR Code Review`.
- `PR Code Review` gom SonarCloud va LLM reviewer.
- Neu Sonar Quality Gate fail hoac LLM thay blocker -> PR check fail.
- Sau khi con nguoi approve va merge PR vao `main` -> chay `Build on main`.

## Workflow files

- `llm-pr-review.yml`: chay khi `pull_request` vao `main`.
  - Build/test .NET trong SonarCloud analysis.
  - Dung SonarCloud de bat style issues, code smells, duplication, security vulnerabilities.
  - Dung LLM de comment review theo kieu human reviewer.
- `ci.yml`: chi chay khi push vao `main` hoac manual dispatch.
  - Restore, build, test.
  - Login Azure, build Docker image, push vao ACR.

## Required repository secrets

Vao GitHub repository -> Settings -> Secrets and variables -> Actions -> New repository secret.

- `SONAR_TOKEN`: SonarCloud token.
- `SONAR_ORG`: SonarCloud organization key.
- `OPENAI_API_KEY`: OpenAI API key cho LLM reviewer.
- `AZURE_CLIENT_ID`: Azure federated credential app/client id.
- `AZURE_TENANT_ID`: Azure tenant id.
- `AZURE_SUBSCRIPTION_ID`: Azure subscription id.

Co the config bang script PowerShell:

```powershell
gh auth login
.\scripts\set-github-secrets.ps1
```

Neu chay script ngoai thu muc repo, truyen repo name vao:

```powershell
.\scripts\set-github-secrets.ps1 -Repo OWNER/REPO
```

Hoac config truc tiep bang GitHub CLI:

```powershell
gh secret set SONAR_TOKEN --repo OWNER/REPO --body "your-sonar-token"
gh secret set SONAR_ORG --repo OWNER/REPO --body "your-sonar-org"
gh secret set OPENAI_API_KEY --repo OWNER/REPO --body "your-openai-api-key"
gh secret set AZURE_CLIENT_ID --repo OWNER/REPO --body "your-azure-client-id"
gh secret set AZURE_TENANT_ID --repo OWNER/REPO --body "your-azure-tenant-id"
gh secret set AZURE_SUBSCRIPTION_ID --repo OWNER/REPO --body "your-azure-subscription-id"
```

## SonarCloud project key

Workflow dang dung project key mac dinh:

```text
${{ github.repository_owner }}_${{ github.event.repository.name }}
```

Vi du: `my-org_gitops-dotnet-api`.

Hay tao project tren SonarCloud voi dung key nay, hoac sua `SONAR_PROJECT_KEY` trong `llm-pr-review.yml`.

## Test flow thuc te

```bash
git checkout -b test/pr-review-flow
echo "// trigger PR review" >> Program.cs
git add Program.cs
git commit -m "test: trigger PR review flow"
git push origin test/pr-review-flow
gh pr create --title "Test PR review flow" --body "Trigger SonarCloud and LLM review" --base main
```

Kiem tra:

- GitHub UI -> tab Pull requests -> PR vua tao -> Checks.
- GitHub UI -> Actions -> `PR Code Review`.
- SonarCloud -> project tuong ung -> Quality Gate.

## Branch protection nen bat

Vao Settings -> Branches -> Add branch protection rule cho `main`.

Bat cac muc sau:

- Require a pull request before merging.
- Require approvals, toi thieu 1 approval.
- Require status checks to pass before merging.
- Chon required checks:
  - `SonarCloud review`
  - `LLM review`

Voi cau hinh nay, flow se la: AI/Sonar review truoc, con nguoi review cuoi, merge xong moi build/publish.
