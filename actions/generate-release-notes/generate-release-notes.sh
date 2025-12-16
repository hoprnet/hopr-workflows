#!/bin/bash
#
# Generate Release Notes
#

set -euo pipefail

# Initialize changelog entries array
declare -a changelog_entries

# Decode the entry of a changelog
jq_decode() {
    echo "${1}" | base64 --decode
}

# Get the creation date of a release tag
# Usage: get_release_date <repo> <tag>
get_release_date() {
    local repo="$1"
    local tag="$2"
    
    gh_api_call "${repo}" "/releases/tags/${tag}" '.created_at'
}

# Fetch merged PRs from a repository between two dates
# Usage: fetch_merged_prs <repo_name> <branch> <start_date> <end_date>
fetch_merged_prs() {
    local repo_name="$1"
    local branch="$2"
    local start_date="$3"
    
    echo "[INFO] Fetching PRs for ${repo_name} (branch: ${branch}) since ${start_date}..." >&2

    local prs=$(gh pr list --state merged --base "$branch" --search "merged:>=$published_at" --json number,title,author | jq -c '.[] | @base64')
    
    if [[ -z "$prs" ]]; then
        echo "[INFO] No PRs found for ${component}" >&2
        return 0
    fi
    
    # Process each PR
    for pr_encoded in ${prs}; do
        local pr_decoded=$(jq_decode "${pr_encoded}")
        
        local id=$(echo "${pr_decoded}" | jq -r '.number')
        local title=$(echo "${pr_decoded}" | jq -r '.title')
        local author=$(echo "${pr_decoded}" | jq -r '.author')

        
        # Extract changelog_type from the title
        # Expected format: "type(component): description" or "type: description"
        # If no colon exists, type defaults to "other"
        if [[ "$title" == *":"* ]]; then
            local changelog_type=$(echo "${title}" | awk -F ':' '{print $1}' | awk -F '(' '{print $1}' | tr '[:upper:]' '[:lower:]' | xargs)
        else
            local changelog_type="other"
        fi
        
        # Trim whitespace from changelog_type
        changelog_type=${changelog_type## }
        changelog_type=${changelog_type%% }
        
        # Add fallback if still empty
        changelog_type=${changelog_type:-"other"}

        # Assign repository as component prefix to distinguish between repos
        echo "[DEBUG] Processing PR: id=${id}, title=${title}, author=${author}, type=${changelog_type}" >&2
        
        # Add to changelog entries array
        changelog_entries+=("$(jq -nc --arg id "$id" \
            --arg title "$title" \
            --arg author "$author" \
            --arg ctype "$changelog_type" \
            '{id:$id,title:$title,author:$author,changelog_type:$ctype}')")
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
    if [[ "$previous_cli_version" != "$current_cli_version" ]] || [[ "$previous_app_version" != "$current_app_version" ]]; then
        change_log_content+="\nThis release contains the following component updates:\n\n"
        
        if [[ "$previous_cli_version" != "$current_cli_version" ]]; then
            change_log_content+="- **[GnosisVPN Client](https://github.com/gnosis/gnosis_vpn-client)**: Updated from [v${previous_cli_version}](https://github.com/gnosis/gnosis_vpn-client/releases/tag/v${previous_cli_version}) to [v${current_cli_version}](https://github.com/gnosis/gnosis_vpn-client/releases/tag/v${current_cli_version})\n"
        fi
        
        if [[ "$previous_app_version" != "$current_app_version" ]]; then
            change_log_content+="- **[GnosisVPN App](https://github.com/gnosis/gnosis_vpn-app)**: Updated from [v${previous_app_version}](https://github.com/gnosis/gnosis_vpn-app/releases/tag/v${previous_app_version}) to [v${current_app_version}](https://github.com/gnosis/gnosis_vpn-app/releases/tag/v${current_app_version})\n"
        fi
        
        change_log_content+="\n"
    fi
    
    # Process each changelog entry
    for entry in "${changelog_entries[@]}"; do
        local id=$(echo "$entry" | jq -r '.id')
        local title=$(echo "$entry" | jq -r '.title')
        local author=$(echo "$entry" | jq -r '.author')
        local component=$(echo "$entry" | jq -r '.component')
        local changelog_type=$(echo "$entry" | jq -r '.changelog_type')
        
        # Determine which section this entry belongs to
        case "$changelog_type" in
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
    local change_log_content="$(printf '%s\n' "${changelog_entries[@]}" | jq -s -c '.')"
    echo -e "${change_log_content}"
}

# Validate input parameters
check_parameters() {
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <repository> <branch> <format>"
        exit 1
    fi
    local branch="$1"
    local format="$2"
    if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
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
            echo "Supported formats: github, debian, json, rpm"
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
        echo "No tag found."
        exit 1
    else
        echo "Last tag on branch ${branch} is $last_tag"
    fi
    
    local release_json=$(gh api repos/${github_repo}/releases/tags/$last_tag)
    local published_at=$(echo "$release_json" | jq -r .published_at)
    if [ -z "$published_at" ]; then
        echo "No release date found."
        exit 1
    else
        echo "Release $last_tag published at $published_at"
    fi
    echo "$published_at"
}

set -x
# Main function
main() {
    local branch="$1"
    local format="$2"
    local release_notes_file="${3:-release_notes.txt}"

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
