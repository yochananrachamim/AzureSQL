#----------------------------------------------------------------
# Application: Query Store Import V.1
# Propose: Import files exported from another QDS to allow Query Store data investigation.
#----------------------------------------------------------------

#----------------------------------------------------------------
#Parameters 
#----------------------------------------------------------------
param($server = "", #ServerName parameter to connect 
      $user = "", #UserName parameter  to connect
      $passwordSecure = "", #Password Parameter  to connect
      $Db = "", #DBName Parameter  to connect
      $Folder = "", #Folder Paramater to save the bcp files 
      $NameSpace = "",
      $DropExisting=1) 


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
    Write-Host "Catch in Log Message"
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



#--------------------------------
# Begin Program
#--------------------------------


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
    if (TestEmpty($NameSpace)) {  $NameSpace = read-host -Prompt "Please enter optiona namespace for the table collection:" }


    #--------------------------------
    #Run the process
    #--------------------------------

    class QSTable {
        [string]$TableName
        [string]$bcpFile
        [string]$xmlFile
        [boolean]$Validated
    
        QSTable([string]$pTableName){
            $this.TableName = $pTableName
            $this.bcpFile = $pTableName + ".bcp"
            $this.xmlFile = $pTableName + ".xml"
        }    
    }

    $LogFile = $Folder + "QDSImport.Log" #Logging the operations.
    $QSLoadList = [System.Collections.ArrayList]::new()
    $ErrorFlag = $false
    $ErrorLog = ""
    
    logMsg -msg "Starting Import" -Color 1

    # Validate Folder, and pair of files exists
    logMsg -msg "Validating folder existance" -Color 1
    if(-not(Test-Path -Path $Folder))
    {
        $ErrorLog = "Path Not Found"
        $ErrorFlag = $true
    }

    logMsg -msg "Load list of files" -Color 1
    $QSLoadList.Clear();
    foreach ($f in ((Get-ChildItem -Path $Folder))) {
        if($f.Extension -in (".bcp"))  {
            [void]$QSLoadList.Add([QSTable]::new($f.BaseName))
        }
    }
    

    # Connecting to database 
    logMsg -msg "Connecting to database" -Color 1
    $SQLConnectionSource = GiveMeConnectionSource #Connecting to the database.
   if($SQLConnectionSource -eq $null)
    { 
     logMsg("It is not possible to connect to the database") (2)
     exit;
    }
   $SQLCmd = New-Object System.Data.SqlClient.SqlCommand("select 1;", $SQLConnectionSource);
   
    # UPSERT StoredProcedure in the destination database to create tables from format file
    $SQLCmd.CommandText = (Get-Content -path GenerateTableFromXMLFormatFile.sql -Raw).Replace("\t"," ").Replace("\n"," ").Replace("\r"," ")
    [void]$SQLCmd.ExecuteNonQuery()
    
  logMsg -msg ("Drop table if exists is set to (0=Keep, 1=Drop): "+$DropExisting) -Color 1
  logMsg -msg ("Loading into namespace: "+$namespace) -Color 1
  logMsg -msg "Creating tables" -Color 1
  
    foreach ($item in $QSLoadList) {
        
        $SQLCmd.CommandText = "exec [dbo].[GenerateTableFromXMLFormatFile] '" + ( Get-Content -Path ($Folder + $item.xmlFile)) +"','"+ $NameSpace+$item.TableName + "',@DropExisting=$DropExisting"
        [void]$SQLCmd.ExecuteNonQuery()

        $Command="BCP " + $NameSpace+$item.TableName  + " in " + $Folder + $item.bcpFile + " -f "+ $Folder + $item.xmlFile +" -S " +$server+" -U " + $user + " -P "+$password+" -d "+$Db
        $Command
        $result = Invoke-Expression -Command $Command
        logMsg("Executed import for table " + $NameSpace+$item.TableName + "-" + $result) 
  }
    
}
catch
  {
    logMsg("QDS Script was executed incorrectly ..: " + $Error[0].Exception) (2)
  }
finally
{
   logMsg("QDS Script finished - Check the previous status line to know if it was success or not") (3)
} 
