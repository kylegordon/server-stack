# GitHub Actions Self-Hosted Runner

This setup provides a self-hosted GitHub Actions runner in a Docker container.

## Setup

1. Edit the `.env` file with your configuration:
   - `REPO_URL`: Your GitHub repository URL (e.g., `https://github.com/username/repo`)
   - Or use `ORG_URL` for organization-level runners
   - `ACCESS_TOKEN`: GitHub Personal Access Token (PAT) with appropriate scope
     - For repo-level: `repo` scope
     - For org-level: `admin:org` scope

2. Customize optional settings:
   - `RUNNER_NAME`: Custom name for your runner
   - `LABELS`: Custom labels (comma-separated)
   - `EPHEMERAL`: Set to `true` for one-time use runners

3. Start the runner:
   ```bash
   docker compose up -d
   ```

4. Check logs:
   ```bash
   docker compose logs -f
   ```

## Creating a GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with:
   - `repo` scope (for repository runners)
   - `admin:org` scope (for organization runners)
3. Copy the token and add it to the `.env` file

## Notes

- The runner has access to Docker (via socket mount) for running containerized actions
- Runner data is persisted in the `./runner-data` directory
- Set `EPHEMERAL=true` for runners that self-destruct after one job
