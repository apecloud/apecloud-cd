#!/usr/bin/env python3
"""
Auto generate release notes by comparing deploy-manifests.yaml between commits.
Supports components with multiple version entries (e.g., kubeblocks with multiple versions).
With --force, generate notes for all components using previous tag (version-1) instead of diff.
Output order respects the order of components in --component YAML file.

Also supports monitoring specific images (e.g., apecloud/dms) defined in --component
with keys prefixed by "image:".

Extended: When kubeblocks-cloud version changes, recursively compare its own manifest
between tags to detect changes in other components/engines.
"""

import subprocess
import sys
import argparse
import re
import os
import yaml
from collections import defaultdict

# ------------------------------------------------------------
# Configuration: images to monitor and their parent component
# ------------------------------------------------------------
MONITORED_IMAGES = {
    "apecloud/apecloud-mcp": "kubeblocks-cloud",
    "apecloud/ape-dts": "kubeblocks-cloud",
    "apecloud/dms": "kubeblocks-cloud",
    "apecloud/oteld": "gemini-monitor",
    "apecloud/servicemirror": "kubeblocks-cloud",
}

# Excluded components from the Components list
EXCLUDED_COMPONENTS = {"kubeblocks-cloud", "kb-cloud-installer"}

# NEW: manifest file name (assumed same in all repos)
MANIFEST_FILE = "deploy-manifests.yaml"

# ------------------------------------------------------------
# Git utility functions
# ------------------------------------------------------------
def run_git_command(cmd, cwd=None, check=True):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=check, cwd=cwd)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if check:
            raise
        return None

def get_git_root(path):
    """Return absolute path of the git root for the given file or directory."""
    if os.path.isfile(path):
        search_dir = os.path.dirname(os.path.abspath(path))
    else:
        search_dir = os.path.abspath(path)
    if not os.path.exists(search_dir):
        return None
    try:
        result = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, cwd=search_dir, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def get_yaml_from_commit(file_path, commit_ref="HEAD"):
    """Load YAML content of file from a specific commit."""
    abs_path = os.path.abspath(file_path)
    git_root = get_git_root(abs_path)
    if not git_root:
        print(f"Error: {abs_path} is not inside a Git repository.")
        return None
    rel_path = os.path.relpath(abs_path, git_root)
    try:
        content = run_git_command(["git", "show", f"{commit_ref}:{rel_path}"], cwd=git_root)
        if content is None:
            return None
        return yaml.safe_load(content)
    except Exception as e:
        print(f"Error reading {commit_ref}:{rel_path}: {e}")
        return None

def get_github_repo_base_url(cwd=None):
    remote_url = run_git_command(["git", "remote", "get-url", "origin"], cwd=cwd)
    match = re.match(r"https?://(?:[^@]+@)?github\.com/(.+?)(?:\.git)?$", remote_url)
    if match:
        return f"https://github.com/{match.group(1)}"
    match = re.match(r"git@github\.com:(.+?)(?:\.git)?$", remote_url)
    if match:
        return f"https://github.com/{match.group(1)}"
    sys.exit(f"Error: Cannot parse GitHub URL from {remote_url}")

def get_repo_name(cwd=None):
    return get_github_repo_base_url(cwd=cwd).split('/')[-1]

def get_previous_tag_for_version(current_tag, repo_path):
    """Given a tag (e.g., v2.2.17), return the previous tag in version-sorted order."""
    try:
        all_tags = run_git_command(["git", "tag", "--sort=version:refname"], cwd=repo_path)
        if not all_tags:
            return None
        tags = [t.strip() for t in all_tags.split('\n') if t.strip()]
        if current_tag not in tags:
            print(f"  Warning: Current tag {current_tag} not found in repository {repo_path}")
            return None
        idx = tags.index(current_tag)
        if idx > 0:
            return tags[idx-1]
        else:
            print(f"  Warning: No previous tag found for {current_tag} in {repo_path}")
            return None
    except Exception as e:
        print(f"  Error getting previous tag: {e}")
        return None

# ------------------------------------------------------------
# Release notes generation
# ------------------------------------------------------------
def extract_pr_numbers(subject):
    return [int(num) for num in re.findall(r'(?<![a-zA-Z0-9])#(\d+)', subject)]

def clean_subject(subject):
    return re.sub(r'\s*\(#\d+(?:,\s*#\d+)*\)\s*$', '', subject).strip()

def load_author(map_file):
    mapping = {}
    if not map_file or not os.path.isfile(map_file):
        return mapping
    with open(map_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '|' in line:
                raw, mapped = line.split('|', 1)
                mapping[raw.strip()] = mapped.strip()
    return mapping

def map_author(author_name, author):
    return author.get(author_name, author_name)

def get_commits_between_tags(old_tag, new_tag, cwd=None, author=None):
    if author is None:
        author = {}
    try:
        repo_base_url = get_github_repo_base_url(cwd=cwd)
        repo_name = get_repo_name(cwd=cwd)

        # Check tags exist
        try:
            run_git_command(["git", "rev-parse", old_tag], cwd=cwd)
            run_git_command(["git", "rev-parse", new_tag], cwd=cwd)
        except subprocess.CalledProcessError:
            return [], None, None, f"Tag {old_tag} or {new_tag} not found"

        raw = run_git_command(["git", "log", "--pretty=format:%H|%s|%an", f"{old_tag}..{new_tag}"], cwd=cwd)
        if not raw:
            return ["* No new commits."], repo_base_url, repo_name, None

        lines = []
        for line in raw.split('\n'):
            if not line.strip():
                continue
            parts = line.split('|', 2)
            if len(parts) < 3:
                continue
            full_hash, subject, author_name = parts
            full_hash = full_hash.strip()
            subject = subject.strip()
            author_name = author_name.strip()

            mapped_author = map_author(author_name, author)
            pr_nums = extract_pr_numbers(subject)
            clean_msg = clean_subject(subject)
            commit_url = f"{repo_base_url}/commit/{full_hash}"

            if pr_nums:
                pr_url = f"{repo_base_url}/pull/{pr_nums[0]}"
                lines.append(f"* {clean_msg} by @{mapped_author} in {pr_url} ({commit_url})")
            else:
                lines.append(f"* {clean_msg} by @{mapped_author} ({commit_url})")

        return lines, repo_base_url, repo_name, None
    except Exception as e:
        return [], None, None, str(e)

def generate_notes_for_project(project_path, old_tag, new_tag, author):
    lines, _, _, err = get_commits_between_tags(old_tag, new_tag, cwd=project_path, author=author)
    if err:
        print(f"  Error in {project_path}: {err}")
        return None
    return "\n".join(lines)

# ------------------------------------------------------------
# NEW: Functions for recursive manifest comparison
# ------------------------------------------------------------
def get_manifest_from_tag(repo_path, tag, manifest_rel_path):
    """Retrieve manifest file content from a specific tag in the given repo."""
    try:
        content = run_git_command(["git", "show", f"{tag}:{manifest_rel_path}"], cwd=repo_path, check=False)
        if content is None:
            print(f"  Error: {manifest_rel_path} not found at tag {tag} in {repo_path}")
            return None
        return yaml.safe_load(content)
    except Exception as e:
        print(f"  Error reading {manifest_rel_path} at {tag} in {repo_path}: {e}")
        return None

def extract_component_versions_with_index(yaml_data):
    """
    Extract version info for each entry in each component.
    Returns a dict: (component_name, entry_index) -> version_string
    Also returns a dict for images: (image_name, parent_component, entry_index) -> version_string
    """
    versions = {}
    image_versions = {}
    if not yaml_data:
        return versions, image_versions
    for comp, entries in yaml_data.items():
        if not isinstance(entries, list):
            entries = [entries]
        for idx, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            if 'version' in entry:
                versions[(comp, idx)] = str(entry['version'])
            # Also extract images for monitored images
            images = entry.get('images', [])
            if isinstance(images, list):
                for img in images:
                    if not isinstance(img, str):
                        continue
                    if ':' not in img:
                        continue
                    img_name, tag = img.rsplit(':', 1)
                    # Only care about monitored images? We'll record all but filter later
                    image_versions[(img_name, comp, idx)] = tag
    return versions, image_versions

def compare_manifests(old_yaml, new_yaml, comp_repo_map, image_repo_map, author, processed_set, recursion_depth=0):
    """
    Compare two manifest YAMLs and return a list of (entry_type, name, idx, old_tag, new_tag, repo_url)
    for all version changes found. Also writes release notes directly to a provided list? We'll collect and let caller handle.
    Returns list of change entries (similar to changed_entries) and list of unmapped changes (comp -> list of (old,new)).
    """
    if recursion_depth > 1:  # prevent infinite recursion (only one level deep is needed)
        return [], {}

    old_versions, old_images = extract_component_versions_with_index(old_yaml) if old_yaml else ({}, {})
    new_versions, new_images = extract_component_versions_with_index(new_yaml) if new_yaml else ({}, {})

    changes = []  # list of (etype, name, idx, old_tag, new_tag, repo_url)
    unmapped = defaultdict(list)

    # Check component version changes
    for (comp, idx), new_ver in new_versions.items():
        # Skip kubeblocks-cloud itself to avoid infinite recursion
        if comp == "kubeblocks-cloud":
            continue
        old_ver = old_versions.get((comp, idx))
        if old_ver is not None and str(old_ver) != str(new_ver):
            # Deduplicate using processed_set
            key = (comp, idx, old_ver, new_ver)
            if key in processed_set:
                continue
            processed_set.add(key)
            # Check if we have repo mapping
            if comp in comp_repo_map:
                repo_path = comp_repo_map[comp]
                if not os.path.isdir(repo_path):
                    print(f"  Warning: Repository path for component '{comp}' does not exist: {repo_path}. Skipping detailed notes.")
                    unmapped[comp].append((old_ver, new_ver))
                    continue
                git_dir = os.path.join(repo_path, '.git')
                if not os.path.isdir(git_dir):
                    print(f"  Warning: {repo_path} is not a Git repository. Skipping detailed notes for {comp}.")
                    unmapped[comp].append((old_ver, new_ver))
                    continue
                try:
                    repo_base_url = get_github_repo_base_url(cwd=repo_path)
                except Exception as e:
                    print(f"  Warning: Failed to get repo URL for {comp}: {e}. Using unmapped fallback.")
                    unmapped[comp].append((old_ver, new_ver))
                    continue
                old_tag = ensure_v_prefix(old_ver)
                new_tag = ensure_v_prefix(new_ver)
                changes.append(('component', comp, idx, old_tag, new_tag, repo_base_url))
            else:
                unmapped[comp].append((old_ver, new_ver))

    # Check monitored image changes (only those in MONITORED_IMAGES)
    for (img_name, parent_comp, idx), new_tag in new_images.items():
        if parent_comp != "kubeblocks-cloud":  # only interested in images from kubeblocks-cloud manifest
            continue
        # Check if this image is one we monitor
        full_img_name = img_name if '/' in img_name else f"apecloud/{img_name}"
        if full_img_name not in MONITORED_IMAGES and img_name not in MONITORED_IMAGES:
            continue
        # Normalize image name to match MONITORED_IMAGES keys
        if full_img_name in MONITORED_IMAGES:
            monitor_key = full_img_name
        elif img_name in MONITORED_IMAGES:
            monitor_key = img_name
        else:
            continue
        old_tag_val = old_images.get((img_name, parent_comp, idx))
        if old_tag_val is not None and old_tag_val != new_tag:
            key = (monitor_key, idx, old_tag_val, new_tag)
            if key in processed_set:
                continue
            processed_set.add(key)
            # For images, we need repo mapping (image_repo_map)
            if monitor_key in image_repo_map:
                repo_path = image_repo_map[monitor_key]
                if not os.path.isdir(repo_path):
                    print(f"  Warning: Repository path for image '{monitor_key}' does not exist: {repo_path}. Skipping detailed notes.")
                    continue
                git_dir = os.path.join(repo_path, '.git')
                if not os.path.isdir(git_dir):
                    print(f"  Warning: {repo_path} is not a Git repository. Skipping detailed notes for image '{monitor_key}'.")
                    continue
                try:
                    repo_base_url = get_github_repo_base_url(cwd=repo_path)
                except Exception as e:
                    print(f"  Warning: Failed to get repo URL for image '{monitor_key}': {e}. Skipping.")
                    continue
                old_tag = ensure_v_prefix(old_tag_val)
                new_tag_ver = ensure_v_prefix(new_tag)
                changes.append(('image', monitor_key, idx, old_tag, new_tag_ver, repo_base_url))
            else:
                # No repo mapping, just record as unmapped? But images are not typical "components"
                # We'll skip because we can't generate notes.
                pass

    return changes, unmapped

# ------------------------------------------------------------
# Core diff logic for components
# ------------------------------------------------------------
def extract_component_versions(yaml_data):
    """
    Extract version info for each entry in each component.
    Returns a dict: (component_name, entry_index) -> version_string
    """
    versions = {}
    if not yaml_data:
        return versions
    for comp, entries in yaml_data.items():
        if isinstance(entries, list):
            for idx, entry in enumerate(entries):
                if isinstance(entry, dict) and 'version' in entry:
                    versions[(comp, idx)] = str(entry['version'])
        elif isinstance(entries, dict) and 'version' in entries:
            versions[(comp, 0)] = str(entries['version'])
    return versions

def extract_image_version(yaml_data, component_name, image_name):
    """
    Extract version (tag) of a specific image from a component's images list.
    Returns (version_string, entry_index) or (None, None) if not found.
    """
    if not yaml_data or component_name not in yaml_data:
        return None, None
    entries = yaml_data[component_name]
    if not isinstance(entries, list):
        entries = [entries]
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            continue
        images = entry.get('images', [])
        for img in images:
            if not isinstance(img, str):
                continue
            # Format: "repo/image:tag" or "image:tag"
            if ':' not in img:
                continue
            img_name, tag = img.rsplit(':', 1)
            if img_name == image_name:
                return tag, idx
    return None, None

def ensure_v_prefix(version):
    v = str(version).strip()
    if not v.startswith('v'):
        return 'v' + v
    return v

def get_base_version(version):
    """
    Extract base version (remove -alpha.x suffix).
    e.g., v2.2.0-alpha.88 -> v2.2.0
    """
    match = re.match(r'(v[\d.]+)-alpha\.\d+$', version)
    if match:
        return match.group(1)
    return version

def get_old_tag_for_kubeblocks_cloud(old_ver, new_ver):
    """
    Determine the old tag for kubeblocks-cloud based on the new version:
    - If new version is -alpha.0: old_tag = base version of old_ver (strip -alpha.x), with v prefix
    - If new version is -alpha.n (n>0): old_tag = v{base}-alpha.{n-1}
    - Otherwise: old_tag = old_ver with v prefix
    """
    new_tag = ensure_v_prefix(new_ver)
    match = re.match(r'v([\d.]+)-alpha\.(\d+)$', new_tag)
    if match:
        base, num_str = match.groups()
        num = int(num_str)
        if num == 0:
            # alpha.0: base version of the manifest old version
            return get_base_version(ensure_v_prefix(old_ver))
        else:
            # alpha.n (n>0): previous alpha version
            return f"v{base}-alpha.{num - 1}"
    # For non-alpha (beta, stable, etc.), use the manifest old version with v prefix
    return ensure_v_prefix(old_ver)

def format_compare_url(repo_base_url, old_tag, new_tag):
    """Format compare URL like https://github.com/owner/repo/compare/old...new"""
    return f"{repo_base_url}/compare/{old_tag}...{new_tag}"

def collect_components_and_engines(yaml_data, monitored_images):
    """
    Returns:
        components: dict name -> list of versions (str)
        engines_entries: dict name -> list of dict with keys 'version' and 'service_versions'
    """
    components = {}
    engines_entries = {}
    if not yaml_data:
        return components, engines_entries

    for comp_name, entries in yaml_data.items():
        if not isinstance(entries, list):
            entries = [entries]
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            version = entry.get('version')
            if version is None:
                continue
            version_str = str(version)
            is_engine = entry.get('type') == 'engine'
            if is_engine:
                service_versions = entry.get('serviceVersions', [])
                sv_list = [str(sv) for sv in service_versions] if service_versions else []
                if comp_name not in engines_entries:
                    engines_entries[comp_name] = []
                engines_entries[comp_name].append({
                    'version': version_str,
                    'service_versions': sv_list
                })
            else:
                # Non-engine components (skip excluded)
                if comp_name in EXCLUDED_COMPONENTS:
                    continue
                if comp_name not in components:
                    components[comp_name] = []
                if version_str not in components[comp_name]:
                    components[comp_name].append(version_str)

    # Add monitored images as components
    for image_name, parent_comp in monitored_images.items():
        version, _ = extract_image_version(yaml_data, parent_comp, image_name)
        if version:
            short_name = image_name.split('/')[-1]
            if short_name not in components:
                components[short_name] = []
            if version not in components[short_name]:
                components[short_name].append(version)

    return components, engines_entries

def auto_release_notes(manifest_path, comp_repo_map, image_repo_map, author_file=None,
                       summary_output="summary_release_notes.md", force=False, list_only=False):
    author = load_author(author_file) if author_file else {}

    abs_manifest = os.path.abspath(manifest_path)
    # Check if manifest file exists
    if not os.path.exists(abs_manifest):
        sys.exit(f"Error: Manifest file {abs_manifest} does not exist.")
    git_root = get_git_root(abs_manifest)
    if not git_root:
        sys.exit(f"Error: {abs_manifest} is not inside a Git repository or the path does not exist.")
    rel_manifest_path = os.path.relpath(abs_manifest, git_root)
    print(f"Manifest relative path: {rel_manifest_path}")

    # Get current YAML from HEAD
    curr_yaml = get_yaml_from_commit(manifest_path, "HEAD")
    if curr_yaml is None:
        sys.exit(f"Error: Could not read {manifest_path} from current HEAD")

    # ---- list_only mode: exit early without any repo operations ----
    if list_only:
        # Get previous YAML for comparison
        if not force:
            prev_yaml = get_yaml_from_commit(manifest_path, "HEAD^")
            if prev_yaml is None:
                print("Warning: No previous version, assuming all components are new")
                prev_comp_versions = {}
                prev_yaml_full = None
            else:
                prev_comp_versions = extract_component_versions(prev_yaml)
                prev_yaml_full = prev_yaml
        else:
            # For --force --list-changed, still compare with HEAD^ (no repo tag lookup)
            prev_yaml = get_yaml_from_commit(manifest_path, "HEAD^")
            if prev_yaml is None:
                prev_comp_versions = {}
                prev_yaml_full = None
            else:
                prev_comp_versions = extract_component_versions(prev_yaml)
                prev_yaml_full = prev_yaml

        curr_comp_versions = extract_component_versions(curr_yaml)

        changed_names = set()
        # Component changes
        for (comp, idx), new_ver in curr_comp_versions.items():
            old_ver = prev_comp_versions.get((comp, idx))
            if old_ver is not None and str(old_ver) != str(new_ver):
                changed_names.add(comp)

        # Image changes
        for image_name, parent_comp in MONITORED_IMAGES.items():
            curr_ver, _ = extract_image_version(curr_yaml, parent_comp, image_name)
            if curr_ver is None:
                continue
            if prev_yaml_full:
                prev_ver, _ = extract_image_version(prev_yaml_full, parent_comp, image_name)
                if prev_ver is not None and prev_ver != curr_ver:
                    short_name = image_name.split('/')[-1]
                    changed_names.add(short_name)
            else:
                # No previous YAML: assume changed
                short_name = image_name.split('/')[-1]
                changed_names.add(short_name)

        # Version follow (no repo required)
        VERSION_FOLLOW = {"kubeblocks-console": "kubeblocks-cloud"}
        for child, parent in VERSION_FOLLOW.items():
            if parent in changed_names and child not in changed_names:
                changed_names.add(child)

        output = ''.join(f'[{n}]' for n in sorted(changed_names))
        print(output if output else "No changes")
        return
    # ---- end list_only early exit ----

    # Always try to get previous YAML (needed for kubeblocks-cloud in --force mode as well)
    prev_yaml = get_yaml_from_commit(manifest_path, "HEAD^")
    if prev_yaml is None:
        if not force:
            # In normal mode, manifest history is mandatory
            print("Warning: No previous version of the manifest found in HEAD^. Assuming all components are new and skipping.")
            return
        else:
            # In force mode, only kubeblocks-cloud requires manifest history; other components can proceed without it
            print("Warning: No previous manifest found; kubeblocks-cloud changes will be skipped.")

    # Collect changes for components
    curr_comp_versions = extract_component_versions(curr_yaml)

    changed_entries = []  # Each entry: (type, name, idx, old_tag, new_tag, repo_url)
    # type can be 'component' or 'image'

    if force:
        print("Force-all mode: generating notes for all components using previous tag (if available).")
        # Process components
        for (comp, idx), new_ver in curr_comp_versions.items():
            if comp not in comp_repo_map:
                print(f"Warning: No repository mapping for component '{comp}', skipping.")
                continue
            repo_path = comp_repo_map[comp]
            # For kubeblocks-cloud, always use manifest history (same as normal mode)
            if comp == "kubeblocks-cloud":
                if prev_yaml is None:
                    print(f"  Skipping {comp}[{idx}] (no previous manifest found)")
                    continue
                prev_comp_versions = extract_component_versions(prev_yaml)
                old_ver = prev_comp_versions.get((comp, idx))
                if old_ver is None:
                    print(f"  Component '{comp}' entry {idx} is new (version {new_ver}), skipping.")
                    continue
                if str(old_ver) != str(new_ver):
                    if not os.path.isdir(repo_path):
                        print(f"  Warning: Repository path for {comp} does not exist: {repo_path}. Skipping detailed notes.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                    git_dir = os.path.join(repo_path, '.git')
                    if not os.path.isdir(git_dir):
                        print(f"  Warning: {repo_path} is not a Git repository. Skipping detailed notes for {comp}.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                    old_tag = get_old_tag_for_kubeblocks_cloud(old_ver, new_ver)
                    new_tag = ensure_v_prefix(new_ver)
                    try:
                        repo_base_url = get_github_repo_base_url(cwd=repo_path)
                    except Exception as e:
                        print(f"  Warning: Failed to get repo URL for {comp}: {e}. Skipping detailed notes.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                    changed_entries.append(('component', comp, idx, old_tag, new_tag, repo_base_url))
                continue

            # For all other components, use git tag lookup
            new_tag = ensure_v_prefix(new_ver)
            old_tag = get_previous_tag_for_version(new_tag, repo_path)
            if old_tag is None:
                print(f"  Skipping {comp}[{idx}] (no previous tag found for {new_tag})")
                continue
            repo_base_url = get_github_repo_base_url(cwd=repo_path)
            changed_entries.append(('component', comp, idx, old_tag, new_tag, repo_base_url))
    else:
        # Normal mode: compare with previous commit
        prev_comp_versions = extract_component_versions(prev_yaml)
        for (comp, idx), new_ver in curr_comp_versions.items():
            old_ver = prev_comp_versions.get((comp, idx))
            if old_ver is None:
                print(f"Component '{comp}' entry {idx} is new (version {new_ver}), skipping.")
                continue
            if str(old_ver) != str(new_ver):
                old_tag = ensure_v_prefix(old_ver)
                new_tag = ensure_v_prefix(new_ver)
                # Use the unified function for kubeblocks-cloud
                if comp == "kubeblocks-cloud":
                    old_tag = get_old_tag_for_kubeblocks_cloud(old_ver, new_ver)
                if comp in comp_repo_map:
                    repo_path = comp_repo_map[comp]
                    # Check path validity
                    if not os.path.isdir(repo_path):
                        print(f"  Warning: Repository path for {comp} does not exist: {repo_path}. Treating as unmapped.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                    git_dir = os.path.join(repo_path, '.git')
                    if not os.path.isdir(git_dir):
                        print(f"  Warning: {repo_path} is not a Git repository. Treating as unmapped for {comp}.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                    try:
                        repo_base_url = get_github_repo_base_url(cwd=repo_path)
                    except Exception as e:
                        print(f"  Warning: Failed to get repo URL for {comp}: {e}. Treating as unmapped.")
                        all_unmapped[comp].append((old_ver, new_ver))
                        continue
                else:
                    repo_base_url = None
                changed_entries.append(('component', comp, idx, old_tag, new_tag, repo_base_url))

    # Process monitored images
    for image_name, parent_comp in MONITORED_IMAGES.items():
        # Get current version
        curr_ver, curr_idx = extract_image_version(curr_yaml, parent_comp, image_name)
        if curr_ver is None:
            print(f"Warning: Image '{image_name}' not found in component '{parent_comp}' current YAML, skipping.")
            continue
        if force:
            # Force-all: use previous tag in git repo
            if image_name not in image_repo_map:
                print(f"Warning: No repository mapping for image '{image_name}', skipping.")
                continue
            repo_path = image_repo_map[image_name]
            if not os.path.isdir(repo_path):
                print(f"  Warning: Repository path for image '{image_name}' does not exist: {repo_path}. Skipping.")
                continue
            git_dir = os.path.join(repo_path, '.git')
            if not os.path.isdir(git_dir):
                print(f"  Warning: {repo_path} is not a Git repository. Skipping detailed notes for image '{image_name}'.")
                continue
            new_tag = ensure_v_prefix(curr_ver)
            old_tag = get_previous_tag_for_version(new_tag, repo_path)
            if old_tag is None:
                print(f"  Skipping image '{image_name}' (no previous tag found for {new_tag})")
                continue
            try:
                repo_base_url = get_github_repo_base_url(cwd=repo_path)
            except Exception as e:
                print(f"  Warning: Failed to get repo URL for image '{image_name}': {e}. Skipping.")
                continue
            changed_entries.append(('image', image_name, curr_idx, old_tag, new_tag, repo_base_url))
        else:
            # Normal mode: compare with previous YAML
            prev_ver, prev_idx = extract_image_version(prev_yaml, parent_comp, image_name)
            if prev_ver is None:
                print(f"Image '{image_name}' is new in component '{parent_comp}', skipping.")
                continue
            if prev_ver != curr_ver:
                old_tag = ensure_v_prefix(prev_ver)
                new_tag = ensure_v_prefix(curr_ver)
                if image_name in image_repo_map:
                    repo_path = image_repo_map[image_name]
                    if not os.path.isdir(repo_path):
                        print(f"  Warning: Repository path for image '{image_name}' does not exist: {repo_path}. Skipping.")
                        continue
                    git_dir = os.path.join(repo_path, '.git')
                    if not os.path.isdir(git_dir):
                        print(f"  Warning: {repo_path} is not a Git repository. Skipping detailed notes for image '{image_name}'.")
                        continue
                    try:
                        repo_base_url = get_github_repo_base_url(cwd=repo_path)
                    except Exception as e:
                        print(f"  Warning: Failed to get repo URL for image '{image_name}': {e}. Skipping.")
                        continue
                    changed_entries.append(('image', image_name, curr_idx, old_tag, new_tag, repo_base_url))

    # Version following for components
    VERSION_FOLLOW = {
        "kubeblocks-console": "kubeblocks-cloud",
        "kb-cloud-installer": "kubeblocks-cloud",
    }
    additional = []
    for child, parent in VERSION_FOLLOW.items():
        parent_changes = [c for c in changed_entries if c[0] == 'component' and c[1] == parent]
        if not parent_changes:
            continue
        # Use the first parent change's versions
        _, _, _, old_ver, new_ver, _ = parent_changes[0]
        # Check if child already has its own change entry
        if any(c[0] == 'component' and c[1] == child for c in changed_entries):
            continue
        if child in comp_repo_map:
            repo_path = comp_repo_map[child]
            child_repo_base_url = get_github_repo_base_url(cwd=repo_path)
            additional.append(('component', child, 0, old_ver, new_ver, child_repo_base_url))
            print(f"Auto-added component '{child}' with version {old_ver} -> {new_ver} (follows '{parent}')")
    changed_entries.extend(additional)

    # ------------------------------------------------------------
    # NEW: Recursive processing for kubeblocks-cloud manifest changes
    # ------------------------------------------------------------
    recursive_changes = []
    recursive_unmapped = defaultdict(list)
    processed_set = set()  # to avoid duplicates across recursion levels

    # Find kubeblocks-cloud entry in changed_entries
    kb_cloud_entry = None
    for entry in changed_entries:
        if entry[0] == 'component' and entry[1] == 'kubeblocks-cloud':
            kb_cloud_entry = entry
            break

    if kb_cloud_entry:
        _, comp_name, idx, old_tag, new_tag, repo_base_url = kb_cloud_entry
        repo_path = comp_repo_map.get(comp_name)
        if repo_path:
            print(f"\nRecursively comparing manifests in {comp_name} from {old_tag} to {new_tag}...")
            old_manifest = get_manifest_from_tag(repo_path, old_tag, rel_manifest_path)
            new_manifest = get_manifest_from_tag(repo_path, new_tag, rel_manifest_path)
            if old_manifest and new_manifest:
                rec_changes, rec_unmapped = compare_manifests(
                    old_manifest, new_manifest, comp_repo_map, image_repo_map, author, processed_set, recursion_depth=0
                )
                recursive_changes.extend(rec_changes)
                # Merge unmapped
                for comp, ver_list in rec_unmapped.items():
                    recursive_unmapped[comp].extend(ver_list)
                print(f"  Found {len(rec_changes)} component(s) changed in kubeblocks-cloud manifest")
            else:
                print(f"  Warning: Could not retrieve manifest from one of the tags ({old_tag}, {new_tag})")
        else:
            print(f"  Warning: No repo mapping for kubeblocks-cloud, cannot recursively process manifests")

    # Merge recursive changes into the main changed_entries list
    # But we need to avoid duplicates: if a component already appears in changed_entries (from top-level diff),
    # we should not add it again. Use processed_set from compare_manifests already handles duplicates.
    changed_entries.extend(recursive_changes)

    # Merge recursive unmapped changes into the main unmapped dict (to be handled later)
    # We'll collect all unmapped changes in a dict for final output
    all_unmapped = defaultdict(list)

    # Process top-level unmapped changes (from direct manifest diff)
    if prev_yaml is not None:
        prev_versions_unmapped = extract_component_versions(prev_yaml)
        curr_versions_unmapped = extract_component_versions(curr_yaml)
        for (comp, idx), new_ver in curr_versions_unmapped.items():
            if comp in comp_repo_map or comp in EXCLUDED_COMPONENTS:
                continue
            old_ver = prev_versions_unmapped.get((comp, idx))
            if old_ver is not None and str(old_ver) != str(new_ver):
                all_unmapped[comp].append((old_ver, new_ver))

    # Add recursive unmapped
    for comp, ver_list in recursive_unmapped.items():
        all_unmapped[comp].extend(ver_list)

    # Deduplicate unmapped version pairs (just in case)
    for comp in all_unmapped:
        all_unmapped[comp] = list(set(all_unmapped[comp]))

    # ------------------------------------------------------------
    # Generate full release notes
    # ------------------------------------------------------------
    has_any_change = bool(changed_entries) or bool(all_unmapped)
    if not has_any_change:
        print("No valid release notes generated.")
        return

    summary_lines = []
    summary_lines.append("## What's Changed")
    summary_lines.append("")

    # Process detailed entries (components with repos and images)
    if changed_entries:
        print(f"Found {len(changed_entries)} version change(s) (including recursive):")
        for etype, name, idx, old, new, _ in changed_entries:
            if etype == 'component':
                print(f"  Component {name}[{idx}]: {old} -> {new}")
            else:
                print(f"  Image {name}: {old} -> {new}")

        for etype, name, idx, old_tag, new_tag, repo_base_url in changed_entries:
            if etype == 'component':
                if name not in comp_repo_map:
                    print(f"Warning: No repository mapping for component '{name}'. Skipping.")
                    continue
                repo_path = comp_repo_map[name]
                if idx == 0 or name in VERSION_FOLLOW.values():
                    display_name = name
                else:
                    display_name = f"{name}[{idx}]"
            else:  # image
                if name not in image_repo_map:
                    print(f"Warning: No repository mapping for image '{name}'. Skipping.")
                    continue
                repo_path = image_repo_map[name]
                short_name = name.split('/')[-1]
                display_name = short_name

            print(f"\nProcessing {display_name} (repo: {repo_path}) from {old_tag} to {new_tag}...")
            notes = generate_notes_for_project(repo_path, old_tag, new_tag, author)
            if notes is None:
                summary_lines.append(f"### {display_name} ({old_tag} → {new_tag}) [ERROR]\n* Failed to generate release notes\n")
            else:
                try:
                    repo_name = get_repo_name(cwd=repo_path)
                except:
                    repo_name = os.path.basename(repo_path)
                if repo_base_url:
                    compare_url = format_compare_url(repo_base_url, old_tag, new_tag)
                    header = f"### {repo_name} ([{old_tag}...{new_tag}]({compare_url}))"
                else:
                    header = f"### {repo_name} ({old_tag} → {new_tag})"
                summary_lines.append(header)
                summary_lines.append("")
                summary_lines.append(notes)
                summary_lines.append("")

    # Process unmapped components/engines (short format)
    if all_unmapped:
        summary_lines.append("### Other Components and Engines")
        summary_lines.append("")
        for comp in sorted(all_unmapped.keys()):
            changes = all_unmapped[comp]
            change_strs = [f"{ensure_v_prefix(old)} → {ensure_v_prefix(new)}" for old, new in changes]
            summary_lines.append(f"- {comp}: {', '.join(change_strs)}")
        summary_lines.append("")

    # Add Components and Engines sections (as tables)
    components_dict, engines_entries = collect_components_and_engines(curr_yaml, MONITORED_IMAGES)

    if components_dict:
        summary_lines.append("## KubeBlocks Cloud Components")
        summary_lines.append("")
        summary_lines.append("| Components | Versions |")
        summary_lines.append("|------------|----------|")
        for comp_name in sorted(components_dict.keys()):
            versions = components_dict[comp_name]
            version_str = ", ".join(versions)
            summary_lines.append(f"| {comp_name} | {version_str} |")
        summary_lines.append("")

    if engines_entries:
        summary_lines.append("## KubeBlocks Cloud Engines")
        summary_lines.append("")
        summary_lines.append("| Engines | Versions | Service Versions |")
        summary_lines.append("|---------|----------|------------------|")
        for engine_name in sorted(engines_entries.keys()):
            entries = engines_entries[engine_name]
            for i, entry in enumerate(entries):
                version = entry['version']
                sv_list = entry['service_versions']
                sv_str = ", ".join(sv_list) if sv_list else ""
                if i == 0:
                    summary_lines.append(f"| {engine_name} | {version} | {sv_str} |")
                else:
                    summary_lines.append(f"| | {version} | {sv_str} |")
        summary_lines.append("")

    with open(summary_output, 'w', encoding='utf-8') as f:
        f.write("\n".join(summary_lines))
    print(f"\n✅ Summary saved to {summary_output}")

# ------------------------------------------------------------
# Main entry point
# ------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Generate release notes from deploy-manifests.yaml diff")
    parser.add_argument("--manifest", default="deploy-manifests.yaml", help="Path to deploy-manifests.yaml (absolute or relative)")
    parser.add_argument("--component", required=True, help="YAML file mapping component name to local repo path, plus optional image: prefix for images")
    parser.add_argument("--author", help="File with author name mapping (raw|github_id)")
    parser.add_argument("--summary", default="summary_release_notes.md", help="Output file")
    parser.add_argument("--force", action="store_true", help="Force generate notes for all components using previous tag")
    parser.add_argument("--list-changed", action="store_true", help="Only output list of changed components/images as [name1][name2]...")
    args = parser.parse_args()

    with open(args.component, 'r', encoding='utf-8') as f:
        raw_map = yaml.safe_load(f)

    comp_repo_map = {}
    image_repo_map = {}
    # Use current working directory as base for relative paths
    base_dir = os.getcwd()
    for key, value in raw_map.items():
        if not os.path.isabs(value):
            abs_path = os.path.normpath(os.path.join(base_dir, value))
        else:
            abs_path = value
        if key.startswith("image:"):
            image_name = key[6:]
            image_repo_map[image_name] = abs_path
        else:
            comp_repo_map[key] = abs_path

    auto_release_notes(args.manifest, comp_repo_map, image_repo_map,
                       args.author, args.summary, args.force,
                       list_only=args.list_changed)

if __name__ == "__main__":
    main()