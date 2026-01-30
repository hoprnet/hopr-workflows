#!/usr/bin/env bash
#
# Generate Release Notes
#

set -euo pipefail

# Initialize changelog entries array
declare -a changelog_entries=()

# Decode the entry of a changelog
jq_decode() {
    echo "${1}" | base64 --decode
}

# Fetch merged PRs from a repository between two dates
# Usage: fetch_merged_prs <repo_name> <branch> <start_date>
fetch_merged_prs() {
    local repo_name="$1"
    local branch="$2"
    local start_datetime="${3}" # Full ISO timestamp
    local start_date="${3%% *}" # Extract YYYY-MM-DD from full ISO timestamp
    
    echo "[INFO] Fetching PRs for ${repo_name} (branch: ${branch}) since ${start_datetime}..." >&2

    local prs=$(gh pr list --state merged --base "$branch" --search "merged:>=$start_date" --json number,title,author,mergedAt | jq -r -c --arg start "$start_datetime" '.[] | select(.mergedAt >= $start) | @base64')
    
    if [[ -z "$prs" ]]; then
        echo "[INFO] No PRs found for ${repo_name}" >&2
        return 0
    fi

    # Process each PR
    for pr_encoded in ${prs}; do
        local pr_decoded=$(jq_decode "${pr_encoded}")

        local id=$(echo "${pr_decoded}" | jq -r '.number')
        local title=$(echo "${pr_decoded}" | jq -r '.title')
        local author=$(echo "${pr_decoded}" | jq -r '.author.login')
        local component="general"
        local type="other"

        # Extract type and component from the title
        # Expected format: "type(component): description" or "type: description"
        if [[ "$title" == *":"* ]]; then
            type=$(echo "${title}" | awk -F ':' '{print $1}' | awk -F '(' '{print $1}' | tr '[:upper:]' '[:lower:]' | xargs)
            # Trim whitespace from type
            type=${type## }
            type=${type%% }
            if [[ "$title" == *"("*"):"* ]]; then
                # Remove type(component): from title
                component=$(echo "${title}" | awk -F '(' '{print $2}' | awk -F ')' '{print $1}' | xargs)
            fi
            title=$(echo "${title}" | awk -F ':' '{print $2}')
            # Trim whitespace from title
            title=${title## }
            title=${title%% }
        fi

        # Assign repository as component prefix to distinguish between repos
        echo "[DEBUG] Processing PR: id=${id}, title=${title}, author=${author}, type=${type}, component=${component}" >&2
        
        # Add to changelog entries array
        changelog_entries+=("$(jq -nc --arg id "$id" \
            --arg title "$title" \
            --arg author "$author" \
            --arg type "$type" \
            --arg component "$component" \
            '{id:$id,title:$title,author:$author,type:$type,component:$component}')")
    done
}

# Build the changelog in GitHub format
github_format_changelog() {
    local section_feature="\n### New Features\n\n"
    local section_fix="\n### Fixes\n\n"
    local section_refactor="\n### Refactor\n\n"
    local section_ci="\n### Automation\n\n"
    local section_documentation="\n### Documentation\n\n"
    local section_other="\n### Other\n\n"
    
    local change_log_content="## What's Changed\n"
    
    # Add summary header
    change_log_content+="\nThis release contains the following changes:\n\n"
    change_log_content+="\n"

    
    # Process each changelog entry
    for entry in "${changelog_entries[@]:-}"; do
        if [[ -z "$entry" ]]; then
            continue
        fi

        local id=$(echo "$entry" | jq -r '.id')
        local title=$(echo "$entry" | jq -r '.title')
        local author=$(echo "$entry" | jq -r '.author')
        local component=$(echo "$entry" | jq -r '.component')
        local type=$(echo "$entry" | jq -r '.type')
        
        # Determine which section this entry belongs to
        case "$type" in
            feat|feature)
                section_feature+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
            fix|bugfix)
                section_fix+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
            refactor)
                section_refactor+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
            ci|cd|chore)
                section_ci+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
            docs|documentation)
                section_documentation+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
            *)
                section_other+="- [${component}] ${title} by @${author} in #${id}\n"
                ;;
        esac
    done
    
    # Add sections that have content
    for section in section_feature section_fix section_refactor section_ci section_documentation section_other; do
        if [[ ${!section} == *" by "* ]]; then
            change_log_content+="${!section}\n"
        fi
    done
    
    echo -e "${change_log_content}"
}

# Build the changelog in JSON format
json_format_changelog() {
    local change_log_content="$(printf '%s\n' "${changelog_entries[@]:-}" | jq -s -c '.')"
    echo -e "${change_log_content}"
}

# Validate input parameters
check_parameters() {
    local branch="${1:-main}"
    local format="${2:-github}"
    if ! git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        echo "Error: Branch '$branch' does not exist."
        exit 1
    else
        echo "Using branch: $branch"
    fi
    case "$format" in
        github|json)
            echo "Using format: $format"
            ;;
        *)
            echo "Error: Unsupported format: ${format}"
            echo "Supported formats: github, json"
            exit 1
            ;;
    esac
}

# Check environment variables
check_env_vars() {
    if [[ -z "${GH_TOKEN:-}" ]]; then
        echo "Error: GH_TOKEN environment variable is not set."
        exit 1
    fi
}

get_last_release_date() {
    local github_repo="$1"
    local branch="$2"
    git fetch --tags --force
    local last_tag=$(git tag --merged origin/${branch} --sort=-creatordate | head -n 1)
    if [ -z "$last_tag" ]; then
        echo "No tags found on branch ${branch}. Using initial commit date." >&2
        published_at=$(git rev-list --max-parents=0 origin/${branch} --date=iso --pretty=format:'%ad' | tail -n 1)
    else
        echo "Last tag on branch ${branch} is $last_tag" >&2
        local release_json=$(gh api repos/${github_repo}/releases/tags/$last_tag)
        local published_at=$(echo "$release_json" | jq -r .published_at)
        if [ -z "$published_at" ]; then
            echo "No release date found." >&2
            exit 1
        else
            echo "Release $last_tag published at $published_at" >&2
        fi
    fi
    

    echo "$published_at"
}

# Main function
main() {
    local branch="${1:-main}"
    local format="${2:-github}"
    local release_notes_file="${3:-release-notes.txt}"

    local github_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    check_parameters "$@"
    check_env_vars

    local last_release_date=$(get_last_release_date ${github_repo} ${branch})
    fetch_merged_prs "${github_repo}" "${branch}" "${last_release_date}"
    echo "Fetched ${#changelog_entries[@]} PRs total" >&2


    case $format in
        github)
            github_format_changelog > "${release_notes_file}"
            ;;
        json)
            json_format_changelog > "${release_notes_file}"
            ;;
        *)
            echo "Error: Unsupported format: ${format}" >&2
            exit 1
            ;;
    esac

    # Display the generated notes
    echo "=========================================="
    cat "${release_notes_file}"
    echo "=========================================="
    echo "Changelog saved to ${release_notes_file}"
}

# Run main function with all arguments
main "$@"
