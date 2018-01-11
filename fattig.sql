/*
  Jesper Johansen
  Miracle A/S
  jjo@miracle.dk
  +45 53 74 71 23

  Failover skal udføres på serveren. hvor AG er sekundær.
  Derfor skal dette oprettes som job på begge servere.

  Det virker således.

  Der oprettes en AG som er master for en gruppe, denne får en Listner, denne AG behøver ikke at indeholde en database.
  de andre ag skal prefikses med samme navn, men får ikke en Listner.
  hvis der skal være læsbart sekundær oprettes der en snapshot ag med egen Listner
  
  eks.
  AG1_master - har Listner
  AG1_Miraclet
  AG1_FraBallerup
  AG1_snapshot - har Listner
  AG2_master - har Listner
  AG2_SvaretEr42

  Applikationerne skal connecte til _master Listner. de vil så se alle databaser på den instance master er primær på. Dog kan kun databaser,
  der er primær på instancen benyttes. nedestående script sørge for at databaser i samme gruppe flyttes automatisk med _master

  Rapport systemer kan connecte til _snapshot, hvis der laves snapshot på sekundær databasen, og derved ikke belaster den primære database.
  dette kræver dog forståelse for snapshot. som jeg ikke kommer ind på her.

  Failover sker ved at udføre følgende
  ALTER AVAILABILITY GROUP [AG1_test] FAILOVER;

  Status på de enkelte AG'er kan ses med denne query
	select ag.name, hars.*
	FROM sys.dm_hadr_availability_replica_states hars
	INNER JOIN sys.availability_groups ag
	  ON ag.group_id = hars.group_id

*/

DECLARE @SQL varchar(max)

/*
Finder først AG'er, der ikke er sammen med sin _master AG.
Hvis master er primær på serveren, udføres der failover på de AG'er der er sekundaær på serveren.
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
Hvis _master er sekundær på serveren og snapshot også er sekundær, udføres der failover på snapshot AG, så den er primær på serveren.
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
