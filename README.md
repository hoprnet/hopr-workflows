# hopr-workflows

GitHub workflows helping HOPR automate tasks via github actions

## Goal Workflow

- A team-member, or an external contributor writes code in a feature branch, or
  in their own fork.

- In most of our repositories the PR should track master. In a select few, we
  may decide that we need a slower release cadence and have a develop branch.

- They create a draft pull-request while they work on the code so we can stay
  up to date on progress.

- Every push to that branch builds and runs the tests.

- When the code is ready, they mark the pull-request as ready to review.

- They add a label indicating whether the code is a major, minor or patch
  release. The default, if no label is given, is a minor release.

- Ideally a team member reviews the code, and indicates approval. For external
  contributors, this is mandatory.

- If the history is messy, the PR is squashed, otherwise it is merged.

- When the PR is merged, an action bumps the package.json and commits that
  change to master/develop.

- A tag is pushed with that code.

- If the version is major|minor then a release is created with that tag.

- That version is pushed to npm





## Technical implementation.

Github makes this needlessly complicated, this is a really basic workflow for a
javascript project, yet all the tooling out there is flawed based on the
limitations of the github action platform.

We need to listen to a 'close' type event on a pull_request action. This is the
only action that allows us to access the labels to work out the type of release.

Based on this, we can have a conditional workflow for each type of release.



Github warts:
 - No easy way to pass the 'label' parameters into tasks. We instead have to
   duplicate our workflows and gate with if conditions.
 - No way to pass parameters to, for example actions/create-release based on the
   code - this needs to come from a git ref. This means we need to base releases
   on tag creation, rather than as part of the pipeline.
 - No way to share all this work between projects. We instead have to copy/paste
   between projects.



Prior Art:
  - [merge release](https://github.com/mikeal/merge-release/blob/master/src/merge-release-run.js)
    doesn't allow for the version to be committed to package.json, therefore
    it's unclear what version is in code.
