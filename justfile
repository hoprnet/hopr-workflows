

tag tagName:
    echo "Updating local tag: {{tagName}}"
    git tag -f {{tagName}}
    echo "Deleting remote tag: {{tagName}}"
    git push --delete origin {{tagName}} || echo "Remote tag {{tagName}} does not exist, skipping deletion."
    echo "Pushing updated tag to remote repository..."
    git push origin {{tagName}}
    echo "Tag {{tagName}} updated successfully."
    