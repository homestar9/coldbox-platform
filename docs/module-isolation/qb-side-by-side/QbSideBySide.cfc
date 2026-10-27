/**
 * Sets up the qb side-by-side experiment for COLDBOX-1478.
 *
 * It installs qb 13.3.1 as the application's copy and qb 11.1.0 as a copy nested in a module called `foo`,
 * renames the class path of the nested copy from `qb` to `foo__qb`, and copies in a test page.
 * Nothing in ColdBox is used or changed. The output folder is git-ignored.
 *
 * Run it from the repository root:
 *
 *     box task run docs/module-isolation/qb-side-by-side/QbSideBySide.cfc
 *
 * Then start any test server and open /tests/results/qb-side-by-side/check.cfm
 */
component {

	/**
	 * Build the experiment folder
	 *
	 * @output The folder to build it in. Defaults to tests/results/qb-side-by-side in this repository.
	 */
	function run( string output = "" ){
		var here = getDirectoryFromPath( getCurrentTemplatePath() )
		var out  = len( arguments.output ) ? arguments.output : here & "../../../tests/results/qb-side-by-side"
		out      = replace( getCanonicalPath( out ), "\", "/", "all" )
		if ( right( out, 1 ) != "/" ) {
			out &= "/"
		}
		print.line( "Building the experiment in #out#" ).toConsole()

		if ( directoryExists( out ) ) {
			directoryDelete( out, true )
		}
		directoryCreate( out, true, true )

		print.line( "Installing qb 13.3.1 as the application's copy..." ).toConsole()
		command( "install" )
			.params( id = "qb@13.3.1", directory = out & "app/modules" )
			.flags( "noSave" )
			.run()

		print.line( "Installing qb 11.1.0 as the copy nested in module foo..." ).toConsole()
		command( "install" )
			.params( id = "qb@11.1.0", directory = out & "foo/modules" )
			.flags( "noSave" )
			.run()

		print.line( "Renaming the class path of the nested copy from qb to foo__qb..." ).toConsole()
		var result = renameClassPath(
			root = out & "foo/modules/qb",
			from = "qb",
			to   = "foo__qb"
		)
		print.line( "  #result.replacements# references changed in #result.files# files" )

		fileCopy( here & "web/Application.cfc", out & "Application.cfc" )
		fileCopy( here & "web/check.cfm", out & "check.cfm" )

		print
			.line()
			.greenLine( "Done. Start a test server and open /tests/results/qb-side-by-side/check.cfm" )
	}

	/**
	 * Rename a module's class path in its own source files, the way the proposed rename command would.
	 *
	 * It changes `from.models.` to `to.models.` wherever it is a class path, and the module's own
	 * `this.cfmapping` line. Nested `modules` folders and `tests` folders are skipped. Files are read
	 * and written as bytes, so line endings, byte order marks and other characters are kept as they are.
	 *
	 * @root The module folder
	 * @from The current mapping name
	 * @to   The new mapping name
	 *
	 * @return { files, replacements }
	 */
	private struct function renameClassPath(
		required root,
		required from,
		required to
	){
		var Pattern     = createObject( "java", "java.util.regex.Pattern" )
		var Matcher     = createObject( "java", "java.util.regex.Matcher" )
		var flags       = Pattern.CASE_INSENSITIVE + Pattern.MULTILINE
		var name        = Pattern.quote( arguments.from )
		// A class path: the mapping name not preceded by a character that would make it part of a longer name
		var classPath   = Pattern.compile( "(^|[^A-Za-z0-9_.@$##/-])" & name & "\.models\.", flags )
		var mappingLine = Pattern.compile( "(this\.cfmapping\s*=\s*)([""'])" & name & "\2", flags )
		var result      = { "files" : 0, "replacements" : 0 }
		var rootPath    = replace( arguments.root, "\", "/", "all" )

		var files = directoryList(
			arguments.root,
			true,
			"path",
			"*.cfc|*.cfm|*.cfml|*.bx|*.bxm|*.bxs"
		)
		for ( var thisFile in files ) {
			var relative = replaceNoCase( replace( thisFile, "\", "/", "all" ), rootPath, "" )
			if ( reFindNoCase( "^/(modules|modules_app|tests)/", relative ) ) {
				continue;
			}

			var original = createObject( "java", "java.lang.String" ).init( fileReadBinary( thisFile ), "ISO-8859-1" )
			var count    = 0

			var m = classPath.matcher( original )
			while ( m.find() ) {
				count++
			}
			var updated = classPath
				.matcher( original )
				.replaceAll( "$1" & Matcher.quoteReplacement( arguments.to ) & ".models." )

			m = mappingLine.matcher( updated )
			while ( m.find() ) {
				count++
			}
			updated = mappingLine
				.matcher( updated )
				.replaceAll( "$1$2" & Matcher.quoteReplacement( arguments.to ) & "$2" )

			if ( count ) {
				fileWrite( thisFile & ".tmp", updated.getBytes( "ISO-8859-1" ) )
				fileMove( thisFile & ".tmp", thisFile )
				result.files++
				result.replacements += count
			}
		}

		return result
	}

}
