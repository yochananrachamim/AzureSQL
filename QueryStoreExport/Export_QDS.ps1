#----------------------------------------------------------------
# Application: Query Store Export V.1
# Propose: Export the details of Query Store Details to bcp files
#----------------------------------------------------------------

#----------------------------------------------------------------
#Parameters 
#----------------------------------------------------------------
param($server = "", #ServerName parameter to connect 
      $user = "", #UserName parameter  to connect
      $passwordSecure = "", #Password Parameter  to connect
      $Db = "", #DBName Parameter  to connect
      $Folder = "") #Folder Paramater to save the bcp files 


#----------------------------------------------------------------
#Function to connect to the database using a retry-logic
#----------------------------------------------------------------

Function GiveMeConnectionSource()
{ 
  for ($i=1; $i -lt 10; $i++)
  {
   try
    {
      logMsg( "Connecting to the database...Attempt #" + $i) (1)
      $SQLConnection = New-Object System.Data.SqlClient.SqlConnection 
      $SQLConnection.ConnectionString = "Server="+$server+";Database="+$Db+";User ID="+$user+";Password="+$password+";Connection Timeout=60" 
      $SQLConnection.Open()
      logMsg("Connected to the database...") (1)
      return $SQLConnection
      break;
    }
  catch
   {
    logMsg("Not able to connect - Retrying the connection..." + $Error[0].Exception) (2)
    Start-Sleep -s 5
   }
  }
}

#--------------------------------------------------------------
#Create a folder 
#--------------------------------------------------------------
Function CreateFolder
{ 
  Param( [Parameter(Mandatory)]$Folder ) 
  try
   {
    $FileExists = Test-Path $Folder
    if($FileExists -eq $False)
    {
     $result = New-Item $Folder -type directory 
     if($result -eq $null)
     {
      logMsg("Imposible to create the folder " + $Folder) (2)
      return $false
     }
    }
    return $true
   }
  catch
  {
   return $false
  }
 }

#-------------------------------
#Create a folder 
#-------------------------------
Function DeleteFile{ 
  Param( [Parameter(Mandatory)]$FileName ) 
  try
   {
    $FileExists = Test-Path $FileNAme
    if($FileExists -eq $True)
    {
     Remove-Item -Path $FileName -Force 
    }
    return $true 
   }
  catch
  {
   return $false
  }
 }

#--------------------------------
#Log the operations
#--------------------------------
function logMsg
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]
         [string] $msg,
         [Parameter(Mandatory=$false, Position=1)]
         [int] $Color
    )
  try
   {
    $Fecha = Get-Date -format "yyyy-MM-dd HH:mm:ss"
    $msg = $Fecha + " " + $msg
    Write-Output $msg | Out-File -FilePath $LogFile -Append
    $Colores="White"
    $BackGround = 
    If($Color -eq 1 )
     {
      $Colores ="Cyan"
     }
    If($Color -eq 3 )
     {
      $Colores ="Yellow"
     }

     if($Color -eq 2)
      {
        Write-Host -ForegroundColor White -BackgroundColor Red $msg 
      } 
     else 
      {
        Write-Host -ForegroundColor $Colores $msg 
      } 


   }
  catch
  {
    Write-Host $msg 
  }
}

#--------------------------------
#The Folder Include "\" or not???
#--------------------------------

function GiveMeFolderName([Parameter(Mandatory)]$FolderSalida)
{
  try
   {
    $Pos = $FolderSalida.Substring($FolderSalida.Length-1,1)
    If( $Pos -ne "\" )
     {return $FolderSalida + "\"}
    else
     {return $FolderSalida}
   }
  catch
  {
    return $FolderSalida
  }
}


#--------------------------------
#Validate Param
#--------------------------------
function TestEmpty($s)
{
if ([string]::IsNullOrWhitespace($s))
  {
    return $true;
  }
else
  {
    return $false;
  }
}


try
{

#--------------------------------
#Check the parameters.
#--------------------------------

if (TestEmpty($server)) { $server = read-host -Prompt "Please enter a Server Name" }
if (TestEmpty($user))  { $user = read-host -Prompt "Please enter a User Name"   }
if (TestEmpty($passwordSecure))  
    {  
    $passwordSecure = read-host -Prompt "Please enter a password"  -assecurestring  
    $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure))
    }
else
    {$password = $passwordSecure} 
if (TestEmpty($Db))  { $Db = read-host -Prompt "Please enter a Database Name"  }
if (TestEmpty($Folder)) {  $Folder = read-host -Prompt "Please enter a Destination Folder (Don't include the past \) - Example c:\QdsExport" }


#--------------------------------
#Run the process
#--------------------------------


logMsg("Creating the folder " + $Folder) (1)
   $result = CreateFolder($Folder) #Creating the folder that we are going to have the results, log and zip.
   If( $result -eq $false)
    { 
     logMsg("Was not possible to create the folder") (2)
     exit;
    }
logMsg("Created the folder " + $Folder) (1)

$sFolderV = GiveMeFolderName($Folder) #Creating a correct folder adding at the end \.

$LogFile = $sFolderV + "QDSExport.Log" #Logging the operations.
$ZipFile = $sFolderV + "QDSExport.Zip" #compress the zip file.

logMsg("Deleting Log and Zip File") (1)
   $result = DeleteFile($LogFile) #Delete Log file
   $result = DeleteFile($ZipFile) #Delete Zip file that contains the results
logMsg("Deleted Log and Zip File") (1)


logMsg("Executing the query to obtain the tables of query store..")  (1)

   $SQLConnectionSource = GiveMeConnectionSource #Connecting to the database.
   if($SQLConnectionSource -eq $null)
    { 
     logMsg("It is not possible to connect to the database") (2)
     exit;
    }
   $SQLCommandExiste = New-Object System.Data.SqlClient.SqlCommand("select name from sys.all_objects where name like '%query_store%' and type = 'V' order by name", $SQLConnectionSource) 
logMsg("Executed the query to obtain the tables of query store..") (1)
   
   $Reader = $SQLCommandExiste.ExecuteReader(); #Executing the Recordset

   while($Reader.Read())
   {

    $FileBCP = $sFolderV + $Reader.GetSqlString(0).ToString() + ".bcp"
    $FileFMT = $sFolderV + $Reader.GetSqlString(0).ToString() + ".xml"

    $CommandFmt="bcp 'sys." + $Reader.GetSqlString(0).ToString() + "' Format nul -f "+$FileFMT + " -rMsSupportRowTerminator -tMsSupportFieldTerminator -c -x -S " +$server+" -U " + $user + " -P "+$password+" -d "+$Db
    $CommandOut="bcp 'sys." + $Reader.GetSqlString(0).ToString() + "' out "+$FileBCP + " -c -rMsSupportRowTerminator -tMsSupportFieldTerminator -S " +$server+" -U " + $user + " -P "+$password+" -d "+$Db
 
    logMsg("Obtain the Format file for " + $FileFMT ) (3)
      $result = Invoke-Expression -Command $CommandFmt
    logMsg("Executed the Format file for " + $FileFMT + "-" + $result) 

    logMsg("Obtain the BCP file for " + $FileBCP )
      $result = Invoke-Expression -Command $CommandOut 
    logMsg("Executed the BCP file for " + $FileBCP + "-" + $result)


   }
   logMsg("Closing the recordset and connection") (1)
     $Reader.Close();
     $SQLConnectionSource.Close() 
     Remove-Variable password
   logMsg("Zipping the content to " + $Zipfile) (1)
      $result = Compress-Archive -Path $Folder\*.log,$Folder\*.bcp,$Folder\*.xml -DestinationPath $ZipFile
   logMsg("Zipped the content to " + $Zipfile + "--" + $result )  (1)
   logMsg("QDS Script was executed correctly")  (1)
}
catch
  {
    logMsg("QDS Script was executed incorrectly ..: " + $Error[0].Exception) (1)
  }
finally
{
   logMsg("QDS Script finished - Check the previous status line to know if it was success or not") (1)
} 
