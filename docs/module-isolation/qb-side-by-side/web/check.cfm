<cfscript>
	/**
	 * Builds a query with each copy of qb and checks that every object in each query
	 * comes from that copy's own files. Run once in the request and once in a thread.
	 */
	results = [];

	function report( label, value ){
		arrayAppend( results, label & ": " & value );
	}

	function pathOf( target ){
		return replace( getMetadata( target ).path, "\", "/", "all" );
	}

	function versionOf( folder ){
		return deserializeJSON( fileRead( expandPath( "/qbSideBySide/#folder#/box.json" ) ) ).version;
	}

	/**
	 * Build a query with the copy behind the given mapping and return the file of every object involved
	 */
	function filesUsedBy( required mappingName ){
		var utils   = createObject( "component", "#mappingName#.models.Query.QueryUtils" ).init();
		var grammar = createObject( "component", "#mappingName#.models.Grammars.MySQLGrammar" ).init( utils );
		var builder = createObject( "component", "#mappingName#.models.Query.QueryBuilder" ).init(
			grammar             = grammar,
			utils               = utils,
			paginationCollector = ""
		);
		var query = builder
			.from( "users" )
			.join( "posts", "users.id", "=", "posts.user_id" )
			.whereRaw( "users.age > ?", [ 18 ] )
			.where( "active", 1 )
			.orderBy( "id" );

		query.toSQL();
		var join = query.getJoins()[ 1 ];

		return {
			"query builder"       : pathOf( query ),
			"grammar"             : pathOf( query.getGrammar() ),
			"grammar parent"      : replace( getMetadata( query.getGrammar() ).extends.path, "\", "/", "all" ),
			"query utilities"     : pathOf( query.getUtils() ),
			"new query"           : pathOf( query.newQuery() ),
			"join clause"         : pathOf( join ),
			"join clause parent"  : replace( getMetadata( join ).extends.path, "\", "/", "all" ),
			"raw expression"      : pathOf( query.raw( "now()" ) )
		};
	}

	function verdict( required files, required folder ){
		var wrong = [];
		for ( var key in files ) {
			if ( !findNoCase( "/#folder#/", files[ key ] ) ) {
				arrayAppend( wrong, key & " came from " & files[ key ] );
			}
		}
		return arrayLen( wrong ) ? "FAIL. " & arrayToList( wrong, "; " ) : "PASS. All #structCount( files )# objects came from its own copy";
	}

	engine = structKeyExists( server, "boxlang" ) ? "BoxLang " & server.boxlang.version : (
		structKeyExists( server, "lucee" ) ? "Lucee " & server.lucee.version : server.coldfusion.productName & " " & server.coldfusion.productVersion
	);
	report( "Engine", engine );
	report( "Application copy", "qb " & versionOf( "app/modules/qb" ) & " at /qb" );
	report( "Nested copy", "qb " & versionOf( "foo/modules/qb" ) & " at /foo__qb" );

	try {
		report( "Nested copy, in the request", verdict( filesUsedBy( "foo__qb" ), "foo/modules/qb" ) );
		report( "Application copy, in the request", verdict( filesUsedBy( "qb" ), "app/modules/qb" ) );
	} catch ( any e ) {
		report( "In the request", "ERROR. " & e.message );
	}

	try {
		threadName = "qbSideBySide_" & createUUID();
		thread name="#threadName#" action="run" {
			try {
				thread.nested      = verdict( filesUsedBy( "foo__qb" ), "foo/modules/qb" );
				thread.application = verdict( filesUsedBy( "qb" ), "app/modules/qb" );
			} catch ( any e ) {
				thread.error = e.message;
			}
		}
		thread action="join" name="#threadName#" timeout="30000";
		finished = cfthread[ threadName ];
		report( "Nested copy, in a thread", finished.nested ?: ( "ERROR. " & ( finished.error ?: "no result" ) ) );
		report( "Application copy, in a thread", finished.application ?: ( "ERROR. " & ( finished.error ?: "no result" ) ) );
	} catch ( any e ) {
		report( "In a thread", "ERROR. " & e.message );
	}

	cfcontent( type = "text/plain", reset = true );
	writeOutput( arrayToList( results, chr( 10 ) ) );
</cfscript>
