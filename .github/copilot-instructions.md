# Git hosting

- Prefer `gh` for GitHub and `glab` for GitLab operations, including merge
  requests, pipelines, job logs, and API requests.
- Reuse persistent OS-keyring authentication. Check `glab --version` and
  `glab auth status --hostname gitlab.com` before authenticated GitLab work.
- This checkout is hosted on GitHub. For GitLab commands, specify the full
  GitLab project URL with `--repo`, or use `glab api --hostname gitlab.com`.
  Pipeline and job requests must use their actual project, which can be a fork
  rather than the merge request's target project.
- Use a browser for interactive OAuth authorization or operations the CLI does
  not support, not as the default GitLab client. Surface CLI errors before
  considering a fallback; never extract browser credentials.
- Never print tokens, request credentials in chat, or store them in the
  repository. Prefer OAuth and OS-keyring storage over plaintext configuration.
- Keep CI waits bounded, report prolonged external waits, and distinguish a
  merged F-Droid recipe from a version published in the official index.

See the [release skill](skills/create-release/SKILL.md) for the release workflow.
