/**
 * Application for the qb side-by-side experiment. Copied into the output folder by QbSideBySide.cfc.
 *
 * Two copies of qb, each with its own mapping:
 * - /qb      the application's copy, qb 13.3.1
 * - /foo__qb the copy nested in module foo, qb 11.1.0, after its class path was renamed
 */
component {

	this.name = "qbSideBySide" & hash( getCurrentTemplatePath() );

	root = getDirectoryFromPath( getCurrentTemplatePath() );

	this.mappings[ "/qbSideBySide" ] = root;
	this.mappings[ "/qb" ]           = root & "app/modules/qb";
	this.mappings[ "/foo__qb" ]      = root & "foo/modules/qb";
	// qb's QueryBuilder creates a cbpaginator object by default
	this.mappings[ "/cbpaginator" ]  = root & "app/modules/qb/modules/cbpaginator";

}
