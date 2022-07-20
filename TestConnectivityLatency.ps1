$ServerName = "<server>.database.windows.net"
$User = "<UserName>"
$Password = "<Password>"
$DatabseName = "master"
$NumOfTests = 100


$stopwatch = New-Object System.Diagnostics.Stopwatch
$stopwatch.Start()
 
$scsb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$scsb["data source"] = $ServerName
$scsb["user"] = $User
$scsb["password"] = $Password
$scsb["initial catalog"] = $DatabseName
$conn = New-Object System.Data.SqlClient.SqlConnection $scsb
 
$Itereations = $NumOfTests
$TotalMS = 0
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT 1"
"Wait..."
for($x=0;$x -lt $Itereations; $x++) {
    Write-Progress -Activity "Testing connectivity" -PercentComplete (100*$x/$Itereations) -CurrentOperation $x
    $stopwatch.Restart()
    $cmd.ExecuteNonQuery() | Out-Null
    $stopwatch.Stop()
    $NonQueryCmdTime = $StopWatch.ElapsedMilliseconds
 
    #"NonQuery:$NonQueryCmdTime"
    $TotalMS = $TotalMS + $NonQueryCmdTime
    #Start-Sleep 1
}
$conn.Close()


$avg = 1.0*$TotalMS/$Itereations
"AVG of $Itereations iterations: $avg ms"
"Done"