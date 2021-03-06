coverage
fileNameFor: aCompiledMethod in: aDirectoryName 
	"Generates the filename for the file where the method related to aCompiledMethod is specified in.
	aDirectoryName (a String) states the subfolder in the projectDirectory where the method comes from."
	| method class package instanceOrClass |
	method := aCompiledMethod selector ifEmpty: [ aCompiledMethod searchForSelector ].
	class := aCompiledMethod methodClass.
	(class isKindOf: Metaclass)
		ifTrue: [
			instanceOrClass := 'class'.
			package := class soleInstance category ]
		ifFalse: [
			instanceOrClass := 'instance'.
			package := class category ].
	^ aDirectoryName, self class slash,
		package, '.package', self class slash,
		class name, '.class', self class slash,
		instanceOrClass, self class slash,
		(method asString replaceAll: $: with: $.), '.st'