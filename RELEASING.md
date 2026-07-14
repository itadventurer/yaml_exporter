# Releasing

Releases are automated: **publish a GitHub Release and CI pushes the gem to
RubyGems** via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
(OIDC — no API key stored anywhere). See `.github/workflows/gem-push.yml`.

## One-time setup

On [rubygems.org](https://rubygems.org) → the `yaml_exporter` gem → **Trusted
Publishers** → *Add* a GitHub Actions publisher:

- Repository: `itadventurer/yaml_exporter`
- Workflow: `gem-push.yml`

The gem already exists on RubyGems, so use the normal *Add* flow above (the
"pending trusted publisher" flow is only for a gem that doesn't exist yet).

Once the publisher is added, the old `RUBYGEMS_AUTH_TOKEN` secret is no longer
used and can be deleted.

## Cutting a release

1. **Bump the version.** Set the new version in `lib/yaml_exporter/version.rb`.
   Open as a normal PR; merge to `main`.

2. **Publish the release** for the matching tag — the workflow expects `vX.Y.Z`
   to equal the version in `version.rb`:

   ```bash
   gh release create v0.2.0 --title v0.2.0 --notes "…"
   ```

   (or use the GitHub UI → *Draft a new release* → pick the tag). Publishing
   fires the workflow, which runs the tests, builds the gem, attaches a
   build-provenance attestation, and pushes it.

That's it — `gem-push.yml` does the build + push; you never touch credentials.

### Versioning

[SemVer](https://semver.org): new backward-compatible features → minor (`0.x`),
bug-fixes → patch. Breaking changes → bump the minor while pre-`1.0`.
