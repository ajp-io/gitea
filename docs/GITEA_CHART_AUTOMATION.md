# Gitea Helm Chart Automation

This project includes automated tooling to keep the Gitea Helm chart up-to-date with the latest upstream releases from the official [Gitea Helm Chart repository](https://gitea.com/gitea/helm-gitea).

## 🤖 How it Works

The automation consists of two main components:

### 1. GitHub Action Workflow (`.github/workflows/update-gitea-chart.yml`)

**Trigger Schedule:** Daily at 9:00 AM UTC via cron schedule
**Manual Trigger:** Can be run manually via GitHub Actions UI

**Process:**
1. **Version Detection**: Compares current chart version in `gitea/Chart.yaml` with the latest version available from the Gitea Helm repository
2. **Update Execution**: If a newer version is found, runs the update script to download and integrate the new chart
3. **PR Creation**: Automatically creates a pull request with the changes, including detailed changelog and verification checklist

### 2. Update Script (`scripts/update-gitea-chart.sh`)

A comprehensive bash script that handles the chart update process:

**Features:**
- ✅ Downloads the latest chart version from upstream
- ✅ Preserves custom configurations and modifications
- ✅ Creates backups of existing configurations
- ✅ Handles file conflicts gracefully (saves as `.custom` files)
- ✅ Provides detailed change summary
- ✅ Includes rollback capabilities via backups

## 🚀 Manual Usage

You can also run the update process manually:

```bash
# Run the update script directly
./scripts/update-gitea-chart.sh

# Or trigger the GitHub Action manually
gh workflow run update-gitea-chart.yml
```

## 📋 What Gets Updated

The automation updates the following:

- **Chart files**: All Helm chart templates, values, and metadata
- **Version info**: Chart.yaml version and app version
- **Dependencies**: Any updated chart dependencies
- **Documentation**: Built-in chart documentation and examples

## 🔧 Preserved Configurations

The following are automatically preserved during updates:

- Custom `values.yaml` modifications
- Custom `.helmignore` entries
- Custom template files in `templates/custom/` directory
- Any other files not present in the upstream chart

### Handling Conflicts

When conflicts occur (upstream changes to files you've customized):
- The upstream version is used
- Your custom version is saved as `filename.custom`
- A warning is displayed for manual review

## 🔍 Pull Request Review Process

When an automated PR is created, please review:

1. **Chart.yaml Changes**: Version bumps, dependency updates, metadata changes
2. **Values.yaml Changes**: New configuration options, deprecated settings, default changes
3. **Template Changes**: New features, bug fixes, breaking changes
4. **Custom Files**: Check for any `.custom` files that need manual merging
5. **Testing**: Deploy to staging environment before merging

## 📚 Repository Structure

```
├── .github/workflows/
│   └── update-gitea-chart.yml    # GitHub Action workflow
├── scripts/
│   └── update-gitea-chart.sh     # Update script
├── gitea/                        # Gitea Helm chart (managed by automation)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── docs/
    └── GITEA_CHART_AUTOMATION.md # This file
```

## 🛠️ Configuration

### GitHub Action Settings

The workflow can be customized by modifying variables in `.github/workflows/update-gitea-chart.yml`:

- `GITEA_CHART_REPO`: Helm repository URL
- `GITEA_CHART_NAME`: Chart name to monitor
- Schedule: Modify the cron expression to change check frequency

### Script Configuration

The update script can be customized by modifying variables at the top of `scripts/update-gitea-chart.sh`:

- `GITEA_CHART_REPO`: Helm repository URL
- `GITEA_CHART_NAME`: Chart name
- Custom file preservation logic

## 🚨 Troubleshooting

### Common Issues

**Issue**: Workflow fails with "Permission denied"
**Solution**: Ensure the script has execute permissions: `chmod +x scripts/update-gitea-chart.sh`

**Issue**: Chart download fails
**Solution**: Check if the Gitea Helm repository is accessible and the chart name is correct

**Issue**: Custom configurations are lost
**Solution**: Check for `.custom` files and manually merge any necessary changes

### Manual Recovery

If the automation breaks something:

1. The script automatically creates backups in `gitea.backup/`
2. Restore from backup: `rm -rf gitea && mv gitea.backup gitea`
3. Or revert the commit/PR if already merged

## 🔐 Security Considerations

- The automation only updates files within the `gitea/` directory
- Custom configurations are preserved and clearly marked
- All changes go through PR review process
- Backups are automatically created before any modifications

## 📈 Monitoring

Monitor the automation via:

- **GitHub Actions**: View workflow runs in the Actions tab
- **Pull Requests**: Review automated PRs with `automated-pr` label
- **Issues**: Report problems with the automation process

---

*Last updated: September 2024*