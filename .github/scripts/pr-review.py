#!/usr/bin/env python3
"""
Claude PR Review Script
Reviews GitHub PRs with special handling for Renovate update PRs.
"""

import os
import re
import sys
import urllib.request
from anthropic import Anthropic
from github import Github, Auth


def get_pr_details():
    token = os.getenv('GITHUB_TOKEN')
    owner = os.getenv('REPO_OWNER')
    repo = os.getenv('REPO_NAME')
    pr_number = int(os.getenv('PR_NUMBER'))

    g = Github(auth=Auth.Token(token))
    repository = g.get_repo(f"{owner}/{repo}")
    pr = repository.get_pull(pr_number)
    return pr, g


def is_renovate_pr(pr):
    return 'renovate' in pr.user.login.lower()


def parse_renovate_update(pr_title):
    """
    Parse Renovate PR title to determine update type.
    Returns (update_type, package, new_version, new_digest)

    Renovate title patterns:
    - "update nginx:1.29.8-alpine docker digest to 582c496"
    - "update docker.io/library/postgres:18 docker digest to 52e6ffd"
    - "update anthropics/claude-code-action digest to 657fb7c"
    - "update nginx docker tag to v1.29.8"
    - "update immich monorepo to v2.7.3"
    - "update renovatebot/github-action action to v46.1.8"
    """
    digest_match = re.search(
        r'update (.+?) (?:docker )?digest to ([a-f0-9]+)', pr_title, re.IGNORECASE
    )
    if digest_match:
        return 'digest', digest_match.group(1).strip(), None, digest_match.group(2)

    tag_match = re.search(
        r'update (.+?) docker tag to v?(\S+)', pr_title, re.IGNORECASE
    )
    if tag_match:
        return 'version', tag_match.group(1).strip(), tag_match.group(2), None

    mono_match = re.search(
        r'update (.+?) (?:monorepo|packages?) to v?(\S+)', pr_title, re.IGNORECASE
    )
    if mono_match:
        return 'version', mono_match.group(1).strip(), mono_match.group(2), None

    # GitHub Actions version update: "update renovatebot/github-action action to v46.1.8"
    action_match = re.search(
        r'update (.+?) action to v?(\S+)', pr_title, re.IGNORECASE
    )
    if action_match:
        return 'version', action_match.group(1).strip(), action_match.group(2), None

    return 'unknown', None, None, None


def fetch_url(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'claude-pr-review-bot'})
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.read().decode('utf-8')
    except Exception as e:
        print(f"Failed to fetch {url}: {e}")
        return None


def get_docker_digest_context(image_name, g):
    """
    For Docker digest-only updates, fetch context explaining what changed.
    Uses docker-library/repo-info for official Docker Hub images.
    """
    image = re.sub(r'^docker\.io/library/', '', image_name).strip()

    if ':' in image:
        repo_name, tag = image.rsplit(':', 1)
    else:
        repo_name, tag = image, 'latest'

    # docker-library/repo-info only covers official (single-name) images
    if '/' in repo_name:
        return None

    result = {}

    # Current image info (platforms, layers, digest)
    info_url = (
        f"https://raw.githubusercontent.com/docker-library/repo-info"
        f"/master/repos/{repo_name}/remote/{tag}.md"
    )
    info_content = fetch_url(info_url)
    if info_content:
        result['repo_info'] = info_content[:2000]

    # Recent commits to this file reveal what triggered the rebuild
    try:
        ri_repo = g.get_repo("docker-library/repo-info")
        path = f"repos/{repo_name}/remote/{tag}.md"
        commits = list(ri_repo.get_commits(path=path))[:3]
        result['recent_commits'] = [
            {
                'date': c.commit.author.date.strftime('%Y-%m-%d %H:%M UTC'),
                'message': c.commit.message.strip()[:300],
                'url': c.html_url,
            }
            for c in commits
        ]
    except Exception as e:
        print(f"Failed to fetch repo-info commits for {image_name}: {e}")

    return result if result else None


def get_github_release_notes(package_name, new_version, old_version, g):
    """
    Fetch GitHub release notes for a version update.
    Only works when package_name looks like owner/repo.
    """
    github_repo = re.sub(r'^(ghcr\.io|docker\.io|quay\.io)/', '', package_name)

    if github_repo.count('/') != 1:
        return None

    def parse_ver(v):
        v = (v or '').lstrip('v')
        try:
            return tuple(int(x) for x in v.split('.'))
        except ValueError:
            return None

    old_ver = parse_ver(old_version)
    new_ver = parse_ver(new_version)

    if not new_ver:
        return None

    try:
        repo = g.get_repo(github_repo)
        results = []
        for release in repo.get_releases():
            tag_ver = parse_ver(release.tag_name)
            if tag_ver is None:
                continue
            if old_ver and tag_ver <= old_ver:
                break
            if tag_ver <= new_ver and release.body:
                results.append({
                    'tag': release.tag_name,
                    'url': release.html_url,
                    'body': release.body[:1500],
                })
            if len(results) >= 5:
                break
        return results if results else None
    except Exception as e:
        print(f"Could not fetch release notes for {github_repo}: {e}")
        return None


def get_old_version_from_diff(files_info):
    """Extract old version from diff lines (lines starting with -)."""
    for f in files_info:
        for line in (f.get('patch') or '').splitlines():
            if line.startswith('-'):
                match = re.search(r'[\s:]v?(\d+\.\d+[\.\d]*)', line)
                if match:
                    return match.group(1)
    return None


def get_pr_data(pr, g):
    files_info = []
    for file in pr.get_files():
        files_info.append({
            'filename': file.filename,
            'additions': file.additions,
            'deletions': file.deletions,
            'patch': file.patch or '',
            'status': file.status,
        })

    renovate = is_renovate_pr(pr)
    update_type, package, new_version, new_digest = None, None, None, None
    digest_context = None
    release_notes = None

    if renovate:
        update_type, package, new_version, new_digest = parse_renovate_update(pr.title)
        print(f"Renovate PR: type={update_type}, package={package}, "
              f"version={new_version}, digest={new_digest}")

        if update_type == 'digest' and package:
            digest_context = get_docker_digest_context(package, g)

        elif update_type == 'version' and package and new_version:
            old_version = get_old_version_from_diff(files_info)
            release_notes = get_github_release_notes(package, new_version, old_version, g)

    return {
        'title': pr.title,
        'body': pr.body or '',
        'author': pr.user.login,
        'is_renovate': renovate,
        'update_type': update_type,
        'package': package,
        'new_version': new_version,
        'new_digest': new_digest,
        'files': files_info,
        'digest_context': digest_context,
        'release_notes': release_notes,
    }


def build_system_prompt():
    return (
        "You are a concise code reviewer. "
        "Use short bullet points. No filler, no praise, no pleasantries. "
        "Only mention issues or noteworthy changes. "
        "If everything looks fine, say so in one line."
    )


def build_review_prompt(pr_data):
    if not pr_data['is_renovate']:
        # Regular (non-Renovate) PR: full diff review
        prompt = (
            f"Review this PR. Be brief - bullet points only.\n\n"
            f"Title: {pr_data['title']}\n"
            f"Description: {pr_data['body']}\n"
            f"Author: {pr_data['author']}\n\n"
            f"Changes:\n"
        )
        for file in pr_data['files']:
            prompt += f"\n### {file['filename']} ({file['status']})\n"
            if file['patch']:
                prompt += f"```diff\n{file['patch'][:2000]}\n```"
        prompt += (
            "\n\nReply with:\n"
            "- **Summary**: 1-2 sentences max\n"
            "- **Security**: Flag any security issues (exposed secrets, injection, "
            "misconfigs, insecure defaults). ALWAYS include this section - either list "
            "issues or say \"No issues\".\n"
            "- **Issues**: List only actual problems (bugs, correctness). Skip if none.\n"
            "- **Suggestions**: Max 3 concrete improvements. Include code snippets only "
            "if helpful. Skip if none.\n\n"
            "Do NOT list categories with \"no issues found\" - except Security, which "
            "must always be present."
        )
        return prompt

    update_type = pr_data['update_type']

    if update_type == 'digest':
        ctx = pr_data.get('digest_context') or {}
        digest_section = ""

        if ctx.get('recent_commits'):
            commits_text = "\n".join(
                f"- {c['date']}: {c['message']} ({c['url']})"
                for c in ctx['recent_commits']
            )
            digest_section += (
                f"Recent changes to image manifest (docker-library/repo-info):\n"
                f"{commits_text}\n\n"
            )

        if ctx.get('repo_info'):
            digest_section += f"Current image info:\n{ctx['repo_info'][:1000]}\n"

        if not digest_section:
            digest_section = "No additional context available for this digest change.\n"

        prompt = (
            f"Renovate digest-only update PR:\n\n"
            f"Title: {pr_data['title']}\n"
            f"Package: {pr_data['package']}\n"
            f"New digest: {pr_data['new_digest']}\n\n"
            f"{digest_section}\n"
            f"Files changed:\n"
        )
        for file in pr_data['files']:
            prompt += f"- {file['filename']} (+{file['additions']}/-{file['deletions']})\n"

        prompt += (
            "\nReply with ONLY this format (no other text):\n\n"
            "| | |\n"
            "|---|---|\n"
            "| **Type** | Digest update |\n"
            "| **Risk** | Low/Medium/High |\n"
            "| **Change** | One sentence explaining WHY the digest changed "
            "(e.g. platform addition, base image rebuild, CVE fix) |\n"
            "| **Security** | None / CVE fixed: ... |\n"
            "| **Action** | None / Manual review needed because ... |\n\n"
            "Base your answer on the repo-info commits above. "
            "If the reason cannot be determined, say so."
        )

    else:
        # Version update
        if pr_data.get('release_notes'):
            combined = "\n\n".join(
                f"### {r['tag']}\n{r['body']}" for r in pr_data['release_notes']
            )
            notes_section = f"GitHub Release Notes:\n{combined[:3000]}"
        elif pr_data.get('body'):
            notes_section = (
                f"Renovate PR Body (may contain release notes):\n"
                f"{pr_data['body'][:3000]}"
            )
        else:
            notes_section = "No release notes available."

        prompt = (
            f"Renovate version update PR:\n\n"
            f"Title: {pr_data['title']}\n"
            f"Package: {pr_data['package']}\n"
            f"New version: {pr_data['new_version']}\n\n"
            f"{notes_section}\n\n"
            f"Files changed:\n"
        )
        for file in pr_data['files']:
            prompt += f"- {file['filename']} (+{file['additions']}/-{file['deletions']})\n"

        prompt += (
            "\nReply with ONLY this format (no other text):\n\n"
            "| | |\n"
            "|---|---|\n"
            "| **Type** | Minor/Patch/Major/Security |\n"
            "| **Risk** | Low/Medium/High |\n"
            "| **Change** | One sentence |\n"
            "| **Security** | None / CVE/GHSA fixed: ... / Security-relevant because ... |\n"
            "| **Action** | None / Manual testing needed because ... |\n\n"
            "IMPORTANT: Carefully check release notes for security advisories (GHSA, CVE), "
            "security fixes, or breaking changes."
        )

    return prompt


def review_with_claude(pr_data):
    client = Anthropic()
    prompt = build_review_prompt(pr_data)
    max_tokens = 400 if pr_data['is_renovate'] else 800

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=max_tokens,
        system=build_system_prompt(),
        messages=[{"role": "user", "content": prompt}]
    )

    return message.content[0].text


def format_github_comment(review, pr_data):
    if pr_data['is_renovate']:
        header = "Renovate PR Summary (by Claude)"
        source_link = ""

        if pr_data.get('release_notes'):
            links = " | ".join(
                f"[{r['tag']}]({r['url']})" for r in pr_data['release_notes']
            )
            source_link = f"\n**Release Notes:** {links}\n"
        elif pr_data.get('digest_context', {}) and \
                pr_data['digest_context'].get('recent_commits'):
            url = pr_data['digest_context']['recent_commits'][0]['url']
            source_link = f"\n**Source:** [docker-library/repo-info]({url})\n"
    else:
        header = "Code Review (by Claude)"
        source_link = ""

    return (
        f"## {header}\n\n"
        f"{review}\n"
        f"{source_link}\n"
        f"---\n"
        f"*Review generated by Claude AI. Please use your judgment for final approval.*\n"
    )


def main():
    try:
        print("Fetching PR details...")
        pr, g = get_pr_details()

        print(f"Analyzing PR #{pr.number}: {pr.title}")
        pr_data = get_pr_data(pr, g)

        print(f"Sending to Claude (Renovate: {pr_data['is_renovate']}, "
              f"type: {pr_data['update_type']})...")
        review = review_with_claude(pr_data)

        print("Formatting comment...")
        comment = format_github_comment(review, pr_data)

        with open('/tmp/claude_review.md', 'w') as f:
            f.write(comment)

        print("Review complete!")
        print(comment)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
