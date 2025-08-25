# 🏷️ Automatic Versioning Guide

This project uses **automatic semantic versioning** based on commit messages. When you push to the main branch, the system automatically creates version tags and Docker images.

## 📝 Commit Message Format

Use these prefixes in your commit messages to control versioning:

### 🔧 **PATCH** Version (1.2.3 → 1.2.4)
*Small fixes, improvements, documentation updates*

```bash
git commit -m "fix: resolve column command dependency in list-regions.sh"
git commit -m "bug: correct file path in Docker container"
git commit -m "docs: update README with new examples"
git commit -m "chore: update dependencies to latest versions"
git commit -m "perf: optimize memory usage for large regions"
git commit -m "refactor: simplify data processing pipeline"
git commit -m "test: add unit tests for region validation"
```

### ✨ **MINOR** Version (1.2.3 → 1.3.0)
*New features, functionality additions*

```bash
git commit -m "feat: add worldwide region support via Geofabrik API"
git commit -m "feat: implement smart caching for downloaded files"
git commit -m "feat: add multi-architecture Docker builds"
```

### 💥 **MAJOR** Version (1.2.3 → 2.0.0)
*Breaking changes, major architectural changes*

```bash
git commit -m "feat!: migrate from Python to pure Bash implementation"
git commit -m "fix!: change Docker image structure (BREAKING CHANGE)"
git commit -m "BREAKING CHANGE: remove deprecated region format support"
```

## 🚀 How It Works

1. **Push to main branch** → CI/CD analyzes commit messages
2. **Determines version bump** → Creates new semantic version tag  
3. **Builds multi-arch Docker images** → Publishes to GitHub Container Registry
4. **Creates tags**: `v1.2.3`, `1.2.3`, `1.2`, `1`, `latest`

## 📋 Quick Reference Card

| Commit Prefix | Version Bump | Example | Use For |
|---------------|--------------|---------|---------|
| `fix:` | PATCH | 1.2.3→1.2.4 | Bug fixes |
| `feat:` | MINOR | 1.2.3→1.3.0 | New features |
| `feat!:` | MAJOR | 1.2.3→2.0.0 | Breaking changes |
| `docs:` | PATCH | 1.2.3→1.2.4 | Documentation |
| `chore:` | PATCH | 1.2.3→1.2.4 | Maintenance |
| `perf:` | PATCH | 1.2.3→1.2.4 | Performance |
| `refactor:` | PATCH | 1.2.3→1.2.4 | Code cleanup |

## ✅ Examples of Good Commit Messages

```bash
# Adding a new feature
git commit -m "feat: add support for European regions in list-regions.sh"

# Fixing a bug
git commit -m "fix: resolve Docker build failure on ARM64 architecture"

# Breaking change (major version bump)
git commit -m "feat!: replace GraphHopper 1.0 with 2.0 (BREAKING CHANGE: old routing files incompatible)"

# Documentation update
git commit -m "docs: add troubleshooting section for memory issues"

# Performance improvement
git commit -m "perf: reduce Docker image size by 200MB"
```

## 🔄 Development Workflow

### For Regular Development:
```bash
# Work on features
git checkout -b feature/new-feature
git commit -m "feat: implement new awesome feature"
git push origin feature/new-feature

# Create PR → merge to main
# No version bump until merged to main
```

### For Releases:
```bash
# Merge PR to main
git checkout main
git pull origin main

# Version is automatically created based on commit messages!
# Check GitHub Actions for new tags and Docker images
```

## 📦 Docker Image Tags Created

When version `1.2.3` is created, you get:
- `ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest`
- `ghcr.io/joshuafuller/atak-vns-offline-routing-generator:1.2.3`
- `ghcr.io/joshuafuller/atak-vns-offline-routing-generator:1.2`
- `ghcr.io/joshuafuller/atak-vns-offline-routing-generator:1`

## 🚨 Important Notes

- **Only commits to main branch trigger versioning**
- **Feature branches don't create versions** (this is intentional)
- **Multiple commits in one PR** → Only highest version bump applies
- **No commit prefix** → No version bump (only `latest` tag updated)

## 🛠️ Manual Override

If you need to create a specific version manually:
```bash
git tag v1.2.3
git push origin v1.2.3
# Triggers build for that specific version
```

---

**Keep this guide handy!** Pin it to your browser or print it out. Consistent commit messages = automatic releases! 🎉