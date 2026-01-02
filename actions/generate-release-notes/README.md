# Release notes

This action generates the release notes of a given repository based on the pull requests merged into the `source_branch` branch (`main`) since the last release.
It identifies the date where the last tag was created in the given branch, and then collects all the pull requests merged in the given branch until now.

## Usage

```bash
      - name: Generate Release Notes
        uses: hoprnet/hopr-workflows/actions/generate-release-notes@generate-release-notes-v1
        with:
          source_branch: ${{ github.ref }}
          format: github
          release_notes_file: ./release-notes.txt
```

## Requirements

- Non nix environment. Ubuntu/Debian runner.


## Inputs

- `source_branch`: The base branch of the PRs merged.
- `format`: The format of the release notes. Accepted values are: `github` and `json`.
- `release_notes_file`:  Filepath of the generated release notes.

## Outputs

None
