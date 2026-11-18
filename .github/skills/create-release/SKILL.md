---
name: create-release
description: 'Create one Okanzo release from latest master/main, including all changes since the previous release, and publish it to GitHub and the official F-Droid catalogue. Use when asked to create a release, release recent features, cut a release, or publish to F-Droid. Uses the remote default branch and the user-authorized GitLab account when metadata updates are needed. Does not publish to Google Play.'
user-invocable: true
---

# Release latest main and publish to F-Droid

Use this workflow when the user requests a release. Creating or reviewing the
skill alone is not authorization to tag, push, or publish.

## Repository context

Re-read the current configuration rather than assuming these values are fixed:

- [Version and dependencies](../../../pubspec.yaml).
- [In-app release highlights](../../../lib/domain/model/release_notes.dart).
- [Signed release workflow](../../workflows/release.yml).
- [Android application, ABI codes, and signing](../../../android/app/build.gradle.kts).
- [Build and quality commands](../../../README.md).
- [Store metadata](../../../fastlane/metadata/android/en-US/).
- [Official F-Droid build recipe](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.cairnlabworks.okanzo.yml).

The repository's default branch is currently `main`, not `master`. Resolve it
with `gh repo view --json defaultBranchRef`; always release its latest fetched
commit unless the user explicitly approves another source.

The application ID is `com.cairnlabworks.okanzo`. Flutter's version is
`versionName+baseVersionCode`; split APK codes currently equal
`baseVersionCode * 10 + 1/2/3` for armeabi-v7a, arm64-v8a, and x86_64.
The workflow builds an AAB and signed APKs but does not publish a GitHub release
or update F-Droid by itself. Google Play is outside this skill's scope.

## 1. Confirm source, version, and access

1. Inspect repository instructions, `git status --short`, branches, worktrees,
   remotes, and GitHub authentication. Prefer `gh` for GitHub and disable pagers.
2. Fetch `origin` and tags. Identify the latest non-draft, stable release and
   compare its tag with the latest remote default branch using both commit
   history and the diff. Handle a first release or divergent history explicitly.
3. Include **all merged changes** in that range in one release. Uncommitted work,
   other local branches, and open pull requests are not included automatically.
   Summarize excluded work and ask before changing that scope.
4. Confirm the version and source with the user. Propose a minor increment for
   added features or a patch increment for fixes; do not reuse a tag or a
   previously published version code.
5. Preserve dirty work. Prepare an isolated worktree/branch from the approved
   source rather than resetting, stashing, or committing unrelated changes.
   Record its source SHA. A previous locally prepared release may be stale;
   do not resume it without comparing it to the current default branch.
6. Verify the four signing secret names are present in GitHub Actions:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
   and `ANDROID_KEY_PASSWORD`. Never display, commit, or attach their values.
7. Fetch the current public F-Droid recipe and inspect its build entries,
   `CurrentVersion`, `CurrentVersionCode`, `AutoUpdateMode`, `UpdateCheckMode`,
   `VercodeOperation`, `Binaries`, and `AllowedAPKSigningKeys`.
   Check existing merge requests before creating a duplicate.
8. Use **GitLab CLI (`glab`) by default** for GitLab merge requests, review
   replies, pipelines, job logs, and API calls. Check `glab --version` and
   `glab auth status --hostname gitlab.com`; reuse the persistent OS-keyring
   login across sessions. A signed-in browser alone does not authenticate glab.
   Authentication is unnecessary for public reads that already work.
9. If glab is missing, use an available package manager; prefer a user-local
   installation when the system package-manager directory is not writable.
   Do not change system permissions or install unrelated packages.
   For a new interactive login, check `glab auth login --help`, then use OAuth:

   ```sh
   glab auth login --hostname gitlab.com --device \
     --git-protocol https --api-protocol https \
     --setup-git-credential-helper
   ```

   Let the user authorize the displayed device code in GitLab. Current glab
   versions use the OS keyring by default; confirm the success message and a
   fresh authenticated API call. Do not use `--insecure-storage`, accept a
   plaintext-storage fallback silently, run `glab auth token`, request tokens
   in chat, or extract browser credentials. A host-scoped glab Git credential
   helper can reuse and refresh OAuth credentials for HTTPS pushes.
   Use a browser only for authorization or a CLI-unsupported operation; report
   CLI failures explicitly rather than silently reverting to browser automation.

## 2. Prepare and validate the release

1. Update `pubspec.yaml` and directly coupled version declarations (including
   `AppReleaseNotes.currentVersion` and the new release's localized highlights in
   `lib/domain/model/release_notes.dart` and `lib/l10n/app_localizations.dart`).
   Check all intended APK codes against F-Droid's existing codes and Android's
   code limit. Keep base AAB codes distinct from multiplied APK codes.
2. Derive full release notes from the complete source range, including features,
   fixes, compatibility changes, and migrations. Review code and commit history;
   do not invent entries or expose private issue details.
3. Add notes to
   `fastlane/metadata/android/en-US/changelogs/<actualVersionCode>.txt` for each
   delivered APK code, and optionally the AAB code. Each file must be at most
   500 characters. Update store descriptions only for verified release features.
   Preserve screenshots and locale metadata unless changes are approved.
4. Use the exact Flutter SDK pinned by the release workflow, with:

   ```sh
   flutter pub get --enforce-lockfile
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test
   ```

   Run device integration checks when relevant and a suitable device is
   available. Report any unrun integration checks explicitly.
5. A baseline failure still needs attention: identify whether it predates the
   release and ask before unrelated corrections. Apply approved formatting/lint
   fixes without behavioral changes. Do not disable checks, suppress failures,
   silently waive them, or treat changed-file-only checks as a full-suite pass.
6. Validate skill frontmatter and repository links if this skill changes.
   Stage only release-related files, commit in the repository's existing style,
   and include the required co-author trailer.

## 3. Tag and build the exact source

1. Present the final version, source/release SHA, included features, checks,
   destinations, and outstanding blockers. Resolve approval before external writes.
2. Re-fetch the default branch before pushing. If it advanced, incorporate the
   new commits and repeat affected checks so "latest" remains accurate.
   Respect branch protection and required pull requests; never bypass checks.
3. Push only the intended release commit/ref. Create an annotated
   `v<versionName>` tag on the final commit and push that tag explicitly.
   Never move an existing tag, force-push, or push every local tag.
4. Identify the tag-triggered `release.yml` run by **both commit and tag**,
   then wait with `gh run watch <run-id> --exit-status`. Diagnose failed steps;
   never substitute an unrelated successful run.
5. Download the named workflow artifact with `gh run download` promptly; its
   current retention is one day. Locate the AAB and all three split APKs.
6. Verify package, version name, actual code, ABI, and signatures using Android
   APK/bundle tools. Confirm every APK certificate matches the current
   `AllowedAPKSigningKeys`, and validate the AAB upload signature. Reject
   debug-signed artifacts: local release builds currently fall back to debug
   signing when `android/key.properties` is absent.
   Run `fdroid scanner --exit-code "$APK"` on each signed APK before publication,
   using current scanner definitions. Reject dependency-metadata signing blocks
   and all other scanner findings; do not bypass them. Android's
   `dependenciesInfo.includeInApk` and `includeInBundle` must remain false.
   Verify the AAB also omits its dependency-metadata entry. Reproducibility and
   signature checks alone do not establish that F-Droid accepts the APK.
7. Preserve verified bytes and generate SHA-256 checksums. The F-Droid
   `Binaries` pattern currently requires these GitHub asset names:

   ```text
   com.cairnlabworks.okanzo_<armeabi-v7aVersionCode>.apk
   com.cairnlabworks.okanzo_<arm64-v8aVersionCode>.apk
   com.cairnlabworks.okanzo_<x86_64VersionCode>.apk
   ```

   Rename the verified files to actual codes, not the base AAB code. Keep the
   matching AAB and a `SHA256SUMS` file. Do not publish signing material.

## 4. Publish and verify GitHub

1. Use `gh release create <tag> --verify-tag` with reviewed notes, title, and
   all verified artifacts/checksums. Mark prereleases appropriately.
2. Verify the release is published, resolves to the expected immutable commit,
   and contains every required asset. Check download URLs and remote digests.
3. On retries, inspect existing releases and asset checksums first. Reuse matching
   results; do not replace different published binaries without explicit approval.

## 5. Publish through official F-Droid

F-Droid publication requires source builds and its own review/build/index cycle.
Uploading APKs to GitHub is **not** proof of F-Droid availability.

Okanzo currently uses an upstream-signed, reproducible-build recipe (`Binaries`
and `AllowedAPKSigningKeys`). F-Droid rebuilds from source and verifies the APKs
against the developer-signed GitHub assets. Do not remove this policy, change the
allowed key, introduce scanner bypasses, or supply a private keystore to F-Droid.

1. Follow the current
   [submission guide](https://f-droid.org/docs/Submitting_to_F-Droid_Quick_Start_Guide/),
   [build metadata reference](https://f-droid.org/docs/Build_Metadata_Reference/),
   and [reproducible-build documentation](https://f-droid.org/docs/Reproducible_Builds/).
2. If the existing auto-update recipe covers the tag/version and still builds
   correctly, use that mechanism. No GitLab login or duplicate merge request is
   necessary. Verify tag detection, new build entries, and build status.
3. If metadata requires changes, use `glab repo fork` to create or reuse the
   authorized account's `fdroid/fdroiddata` fork and submit a minimal merge
   request with `glab mr create`. Inspect each command's help before use, avoid
   adding fork remotes to the unrelated GitHub checkout, and work in the
   isolated F-Droid checkout. For a cross-fork request, explicitly select the
   upstream `--repo`, authorized fork `--head`, source branch and target branch;
   supply a reviewed title/description and `--yes` for noninteractive creation.
   Use `glab mr update` and `glab mr note` for follow-up changes and reviewer
   replies instead of browser API writes. Preserve the existing
   ABI strategy, anti-features, signing identity, and reproducibility policy.
   Update all applicable `Builds` entries with correct `versionName`,
   `versionCode`, immutable `commit`, `CurrentVersion`, and `CurrentVersionCode`.
4. Pin the same compatible Flutter/build dependencies as the release. Use
   F-Droid's per-ABI targets (`android-arm`, `android-arm64`, `android-x64`) and
   existing recipe as prior art. Check source-scanner and dependency eligibility
   for new plugins. Do not invent an untested recipe.
5. Run `fdroid lint com.cairnlabworks.okanzo` and applicable scan/build checks in
   a suitable environment, selecting the intended version codes explicitly.
   Verify GitLab CI if local F-Droid tools/build infrastructure are unavailable;
   record which checks actually ran. Use glab to inspect the exact MR head
   commit and its pipeline, not merely the newest pipeline on a branch.
   From this GitHub-hosted repository, use explicit GitLab hosts/projects:

   ```sh
   glab mr view "$MR_IID" --repo https://gitlab.com/fdroid/fdroiddata
   glab api --hostname gitlab.com \
     "projects/fdroid%2Ffdroiddata/merge_requests/$MR_IID" |
     jq '{sha, state, pipeline: .head_pipeline}'
   glab api --hostname gitlab.com \
     "projects/$PIPELINE_PROJECT_ID/pipelines/$PIPELINE_ID/jobs" \
     --paginate | jq '.[] | {id, name, status, web_url}'
   glab ci trace "$JOB_ID" --repo "https://gitlab.com/$PIPELINE_PROJECT_PATH"
   ```

   Set these variables from the verified MR/pipeline response. In particular,
   `head_pipeline.project_id` may identify the user's fork rather than
   `fdroid/fdroiddata`; use that project for pipeline status, job traces and
   artifacts. Use `glab api` for CLI-unsupported endpoints, with explicit request
   methods for writes. Filter its JSON with external `jq`, not GitHub CLI's
   `--jq` flag. Keep waits bounded and retrieve large logs into temporary files
   for targeted reads; do not dump credentials or entire verbose logs.
6. If reproducibility fails, inspect official build logs and compare unsigned
   APK contents/signing inputs. Align the build environment or recipe, validate
   the correction, and submit it for review. Do not silently replace published
   assets or claim a signature-only check proves reproducibility.
7. Track merge-request review, build and reproducibility verification, and
   official index publication for **each ABI code**. Use the
   [F-Droid app listing](https://f-droid.org/packages/com.cairnlabworks.okanzo/)
   and official repository index as availability evidence.
8. If credentials, CI, review, or build infrastructure block progress, report
   the exact blocker and provide a validated patch or next action. External
   delays may require a later follow-up; do not poll indefinitely.

## 6. Report the verified outcome

Report the source/tag, included changes, test results, checksums, and evidence:

| Destination | Version/code | Status | Evidence or blocker |
| --- | --- | --- | --- |
| GitHub | Release tag | Published / blocked | Release and asset verification |
| Official F-Droid | Each ABI code | Awaiting auto-update / submitted / pending build / available / blocked | Metadata, merge request, build logs, or official index |

Distinguish "submitted", "scheduled", "verified build", and "available". Do not
claim both destinations are published until the official F-Droid index contains
the intended versions. Google Play is not part of this workflow.
Clean up temporary files/worktrees created by the workflow after preserving
requested deliverables. Never delete or reset the user's original worktree.
