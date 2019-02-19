/*
  Jesper Johansen
  Miracle A/S
  jjo@miracle.dk
  +45 53 74 71 23

  Failover skal udføres på serveren. hvor AG er sekundær.
  Derfor skal dette oprettes som job på begge servere.

  Det virker således.

  Der oprettes en AG som er master for en gruppe, denne før en Listner, denne AG behøver ikke at indeholde en database.
  de andre ag skal prefikses med samme navn, men f�r ikke en Listner.
  hvis der skal være l�sbart sekund�r oprettes der en snapshot ag med egen Listner
  
  eks.
  AG1_master - har Listner
  AG1_Miraclet
  AG1_FraBallerup
  AG1_snapshot - har Listner
  AG2_master - har Listner
  AG2_SvaretEr42

  Applikationerne skal connecte til _master Listner. de vil s� se alle databaser p� den instance master er prim�r p�. Dog kan kun databaser,
  der er prim�r p� instancen benyttes. nedest�ende script s�rge for at databaser i samme gruppe flyttes automatisk med _master

  Rapport systemer kan connecte til _snapshot, hvis der laves snapshot p� sekund�r databasen, og derved ikke belaster den prim�re database.
  dette kr�ver dog forst�else for snapshot. som jeg ikke kommer ind p� her.

  Failover sker ved at udf�re f�lgende
  ALTER AVAILABILITY GROUP [AG1_test] FAILOVER;

  Status p� de enkelte AG'er kan ses med denne query
	select ag.name, hars.*
	FROM sys.dm_hadr_availability_replica_states hars
	INNER JOIN sys.availability_groups ag
	  ON ag.group_id = hars.group_id

*/

DECLARE @SQL varchar(max)

/*
Finder f�rst AG'er, der ikke er sammen med sin _master AG.
Hvis master er prim�r p� serveren, udf�res der failover p� de AG'er der er sekunda�r p� serveren.
Samler failover i et sql.
*/
SELECT @SQL = COALESCE(@SQL,'') + CHAR(13) + CHAR(10) + 'ALTER AVAILABILITY GROUP [' + ag.name + '] FAILOVER;'
FROM sys.dm_hadr_availability_replica_states hars
INNER JOIN sys.availability_groups ag
  ON ag.group_id = hars.group_id
WHERE 1=1
AND hars.role_desc <> 'PRIMARY' 
and hars.is_local = 1
AND PATINDEX('%_master', ag.name ) = 0
AND PATINDEX('%_snapshot', ag.name ) = 0
AND LEFT(ag.name,CHARINDEX('_',ag.name)) in
    (SELECT REPLACE(agm.name,'master','')
	 FROM sys.dm_hadr_availability_replica_states harsm
	 INNER JOIN sys.availability_groups agm
	   ON agm.group_id = harsm.group_id
	 WHERE 1=1 
  	   AND harsm.is_local = 1
	   AND harsm.role_desc = 'PRIMARY' 
	   AND PATINDEX('%_master', agm.name ) > 0);

/*
Finder derefter _snapshot AG'er der ikke er modsat sin _master AG.
Hvis _master er sekund�r p� serveren og snapshot ogs� er sekund�r, udf�res der failover p� snapshot AG, s� den er prim�r p� serveren.
Samler failover i et sql.
*/
SELECT @SQL = COALESCE(@SQL,'') + CHAR(13) + CHAR(10) +
             'ALTER AVAILABILITY GROUP [' + ag.name + '] FAILOVER;'
FROM sys.dm_hadr_availability_replica_states hars
INNER JOIN sys.availability_groups ag
  ON ag.group_id = hars.group_id
WHERE 1=1
AND hars.role_desc = 'SECONDARY' 
and hars.is_local = 1
AND PATINDEX('%_snapshot', ag.name ) > 0
AND  LEFT(ag.name,CHARINDEX('_',ag.name)) in
    (select REPLACE(agm.name,'master','')
	FROM sys.dm_hadr_availability_replica_states harsm
	INNER JOIN sys.availability_groups agm
	  ON agm.group_id = harsm.group_id
	WHERE 1=1 
	AND harsm.is_local = 1
	AND harsm.role_desc = 'SECONDARY' 
	AND PATINDEX('%_master', agm.name ) > 0)

PRINT ISNULL(@sql,'Intet at lave')

EXEC (@sql)
