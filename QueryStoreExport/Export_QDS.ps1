#Source Database - Connectivity details User DB and master DB
$server= "tcp:servername.database.windows.net,1433"
$user="username"
$password="password"
$Db="Databasename"
$Folder = "C:\folder"


#Function to connect to the database
Function GiveMeConnectionSource{ 
  for ($i=0; $i -lt 10; $i++)
  {
   try
    {
      $SQLConnection = New-Object System.Data.SqlClient.SqlConnection 
      $SQLConnection.ConnectionString = "Server="+$server+";Database="+$Db+";User ID="+$user+";Password="+$password+";Connection Timeout=60" 
      $SQLConnection.Open()
      break;
    }
  catch
   {
    Start-Sleep -s 5
   }
  }
   Write-output $SQLConnection
}

#Create a folder 
Function CreateFolder{ 
  Param( $Folder ) 
  try
   {
    $FileExists = Test-Path $Folder
    if($FileExists -eq $False)
    {
     New-Item $Folder -type directory
    }
    write-output 1
   }
  catch
  {
   write-output 0
  }
 }

try
{
Clear-Host

CreateFolder $Folder

$SQLConnectionSource = GiveMeConnectionSource
$SQLCommandExiste = New-Object System.Data.SqlClient.SqlCommand("select * from sys.all_objects where name like '%query_store%' and type = 'V'", $SQLConnectionSource) 
$Reader = $SQLCommandExiste.ExecuteReader(); 
 while($Reader.Read())
   {
    $File = $Folder + "\"+$Reader.GetSqlString(0).ToString() + ".bcp"
    $ComandoOut=“bcp 'sys." + $Reader.GetSqlString(0).ToString() + "' out "+$File + " -c -S " +$server+" -U " + $user + " -P "+$password+" -d "+$Db
    $Fecha = Get-Date -format "yyyyMMddHHmmss"
    Write-Host  $Fecha " // " $ComandoOut
    Invoke-Expression -Command $ComandoOut 
   }
   $Reader.Close();
   $SQLConnectionSource.Close() 
}
catch
  {
    Write-Host -ForegroundColor DarkYellow "You're WRONG"
    Write-Host -ForegroundColor Magenta $Error[0].Exception
  }
finally
{
   Write-Host -ForegroundColor Cyan "It's finally over..."
} 
