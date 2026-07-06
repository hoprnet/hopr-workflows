# Break-glass only: release tags are normally created by the Release Tags
# workflow (.github/workflows/release-tags.yaml). Use this recipe only to
# repair an alias tag when the automation cannot.
tag tagName:
    echo "Updating local tag: {{tagName}}"
    git tag -f {{tagName}}
    echo "Deleting remote tag: {{tagName}}"
    git push --delete origin {{tagName}} || echo "Remote tag {{tagName}} does not exist, skipping deletion."
    echo "Pushing updated tag to remote repository..."
    git push origin {{tagName}}
    echo "Tag {{tagName}} updated successfully."
