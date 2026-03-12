# GitHub Secrets Setup for JFrog Integration

This guide explains how to configure GitHub secrets for JFrog integration when OIDC is not available (non-Enterprise subscriptions).

## When to Use Secret-Based Authentication

Use secret-based authentication when your JFrog subscription does NOT support OIDC:
- `enterprise` (base, without xray/plus suffix)
- `pro` / `pro_x`
- `oss` / `community`

To check your subscription type:
```bash
# Load credentials from .env
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/license" | jq -r '.subscriptionType'
```

OIDC is only available for `enterprise_xray*` or `enterprise_plus*` subscriptions.

## Required GitHub Secrets

### For npm Workflows

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `JFROG_URL` | Full JFrog Platform URL | `https://mycompany.jfrog.io` |
| `JFROG_ACCESS_TOKEN` | JFrog access token with deploy permissions | `eyJ...` |

### For Docker Workflows

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `JFROG_URL` | Full JFrog Platform URL | `https://mycompany.jfrog.io` |
| `JFROG_ACCESS_TOKEN` | JFrog access token with deploy permissions | `eyJ...` |
| `JFROG_USERNAME` | JFrog username (required for docker login) | `user@email.com` |

## Step-by-Step Setup

### Step 1: Generate a JFrog Access Token

1. Log in to your JFrog Platform
2. Navigate to **User Menu** (top right) > **Edit Profile** > **Access Tokens**
3. Or go directly to: `https://your-platform.jfrog.io/ui/admin/configuration/security/access_tokens`
4. Click **Generate Token**
5. Configure the token:
   - **Description**: `GitHub Actions - {repo-name}`
   - **Expiration**: Set an appropriate expiration (recommend at least 1 year for CI)
   - **Scope**: Select the project or repositories the token can access
6. Click **Generate** and copy the token immediately (you won't see it again)

**Recommended token permissions:**
- Read and Deploy permissions on the npm/Docker repositories

### Step 2: Add Secrets to GitHub Repository

#### Via GitHub UI

1. Go to your GitHub repository
2. Navigate to **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Add each secret:

**JFROG_URL:**
- Name: `JFROG_URL`
- Value: `https://your-company.jfrog.io`

**JFROG_ACCESS_TOKEN:**
- Name: `JFROG_ACCESS_TOKEN`
- Value: (paste the access token)

**JFROG_USERNAME** (for Docker only):
- Name: `JFROG_USERNAME`
- Value: (your JFrog username or email)

### Step 3: Verify Secrets Are Set

Go to **Settings** > **Secrets and variables** > **Actions** in your repository.

You should see:
- `JFROG_URL`
- `JFROG_ACCESS_TOKEN`
- `JFROG_USERNAME` (if using Docker)

The values are hidden but you can update them anytime.

## Using Secrets in Workflows

The secret-based workflow templates are pre-configured to use these secrets.

**npm workflows** use JFrog CLI:
```yaml
- name: Setup JFrog CLI
  uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ secrets.JFROG_URL }}
    JF_ACCESS_TOKEN: ${{ secrets.JFROG_ACCESS_TOKEN }}
```

**Docker workflows** use vanilla docker (no JFrog CLI):
```yaml
- name: Authenticate Docker with JFrog
  run: |
    echo "${{ secrets.JFROG_ACCESS_TOKEN }}" | docker login ${{ env.JFROG_HOST }} \
      --username ${{ secrets.JFROG_USERNAME }} \
      --password-stdin
```

## Security Best Practices

### Token Management

1. **Use minimal permissions**: Only grant the token access to the repositories it needs
2. **Set expiration**: Don't create tokens that never expire
3. **Rotate regularly**: Update tokens periodically (at least annually)
4. **Audit usage**: Monitor token usage in JFrog's audit logs

### Secret Handling

1. **Never log secrets**: Ensure workflows don't accidentally print secret values
2. **Limit access**: Only repository admins should manage secrets
3. **Use environments**: For production deployments, use GitHub Environments with protection rules

### Organization-Wide Secrets

For multiple repositories, consider using organization secrets:

1. Go to **Organization Settings** > **Secrets and variables** > **Actions**
2. Create secrets there instead
3. Grant access to specific repositories

This avoids duplicating secrets across repos.

## Troubleshooting

### Authentication Failed

```
Error: 401 Unauthorized
```

**Check:**
1. Token is correctly copied (no extra spaces)
2. Token hasn't expired
3. Token has access to the required repositories
4. `JFROG_URL` includes `https://`

### Docker Login Failed

```
Error: unauthorized: authentication required
```

**Check:**
1. `JFROG_USERNAME` is set correctly
2. Username matches the token's owner
3. Token has Docker repository permissions
4. The JFrog host is correct in the workflow env vars

### Token Expired

Generate a new token in JFrog and update the `JFROG_ACCESS_TOKEN` secret in GitHub.

## Comparison: Secrets vs OIDC

| Aspect | Secrets | OIDC |
|--------|---------|------|
| Setup complexity | Simple | Moderate (requires JFrog admin) |
| Secret rotation | Manual | Not needed |
| Token lifetime | Long-lived | Short-lived (per-workflow) |
| Security | Good | Better |
| Subscription | Any | Enterprise Xray/Plus only |
| Audit trail | Limited | Detailed per-workflow |

If your subscription supports OIDC, consider upgrading to use it for better security.

## Next Steps

1. Copy the appropriate workflow template to `.github/workflows/`
2. Replace the placeholders (`{PROJECT_KEY}`, `{JFROG_HOST}`, etc.)
3. Commit and push
4. Monitor the Actions tab for successful builds
