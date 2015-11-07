| gitPath gitCache |
Transcript cr; show: 'travis---->travisCI.st'.

gitCache := 'git_cache'.
gitPath := (Smalltalk at: #'FileDirectory' ifAbsent: [  ])
  ifNil: [ ((Smalltalk at: #'FileSystem') workingDirectory / gitCache) pathString ]
  ifNotNil: [:fileDirectoryClass | (fileDirectoryClass default directoryNamed: gitCache ) fullName].

Metacello new
  baseline: 'SWTDemo';
  repository: 'filetree://', gitPath, '/smalltalkCI/packages';
  get.

Metacello new
  baseline: 'SWTDemo';
  repository: 'filetree://', gitPath, '/smalltalkCI/packages';
  load: 'TravisCI'.

"Run the tests"
TravisCIHarness
  value: #( 'BaselineOfSWTDemo' )
  value: 'TravisCISuccess.txt' 
  value: 'TravisCIFailure.txt'.
