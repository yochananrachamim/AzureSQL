#######################################################################################################################
##  DeadLock Generator
##
##  Description and usage: 
##      This PS script is used to generate high volumne of deadlocks
##      There are no prerequesites on the destination database, and no leftovers will be in the destination DB. 
##      
##  How to use: 
##      Set the parameters at the top of the script and run. 
##
## Yochanan Rachamim - Jan 2023
#######################################################################################################################


# Parameters
$pNumberOfDeadlocksToGenerate = 10
$pServerName = '{ServerName}.database.windows.net'
$pDatabaseName = 'master'
$pUserName ='{LoginName}'
$pPassword = '{password}'

# Initilize variables
$connectionString = 'Server=tcp:{0},1433;Initial Catalog={1};Persist Security Info=False;User ID={2};Password={3};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;' `
 -f $pServerName,$pDatabaseName,$pUserName,$pPassword
$iTableName = '##dltab' + (New-Guid).ToString()
$iSafetyWaitms = 100
$iNumberOfExceptions = 0 

# Create connection objects
$sqlConnection0 = New-Object System.Data.SqlClient.SqlConnection $connectionString
$sqlConnection1 = New-Object System.Data.SqlClient.SqlConnection $connectionString
$sqlConnection2 = New-Object System.Data.SqlClient.SqlConnection $connectionString

# Create command objects
$sqlCMD0 = New-Object System.Data.SqlClient.SqlCommand
$sqlCMD1 = New-Object System.Data.SqlClient.SqlCommand
$sqlCMD2 = New-Object System.Data.SqlClient.SqlCommand

# Set command's connection
$sqlCMD0.Connection = $sqlConnection0
$sqlCMD1.Connection = $sqlConnection1
$sqlCMD2.Connection = $sqlConnection2

# Preparing database environment by creating tables for deadlock reproduction.
$sqlConnection0.Open()
$sqlCMD0.CommandText = '
    -- Environment preperation 
    -- create two tables with one record each, so we can cross lock the records and generate deadlock. 
    CREATE TABLE ['+$iTableName+'1] (i int)
    CREATE TABLE ['+$iTableName+'2] (i int)
    INSERT INTO ['+$iTableName+'1] VALUES(0)
    INSERT INTO ['+$iTableName+'2] VALUES(0)
    '
$null =  $sqlCMD0.ExecuteNonQuery();
# need to keep Connection0 opened as it keeps the temp tables alive. 

# loop to produce deadlock.
for ($i = 1; $i -le $pNumberOfDeadlocksToGenerate; $i++) {
        try {
            "Generating deadlock " + $i.ToString()
            
            # make sure connections are opened.
            if($sqlConnection1.State -ne "open") {$sqlConnection1.Open()}
            if($sqlConnection2.State -ne "open") {$sqlConnection2.Open()}
            
            # begin transaction so we will keep the lock on the records. 
            $sqlCMD1.Transaction = $sqlConnection1.BeginTransaction()
            $sqlCMD2.Transaction = $sqlConnection2.BeginTransaction()

            $sqlCMD1.CommandText = "update [" + $iTableName +"1] set i=1"
            $sqlCMD2.CommandText = "update [" + $iTableName +"2] set i=1"
            $null =  $sqlCMD1.ExecuteNonQuery()
            $null =  $sqlCMD2.ExecuteNonQuery()

            $sqlCMD1.CommandText = "update [" + $iTableName +"2] set i=1"
            $sqlCMD2.CommandText = "update [" + $iTableName +"1] set i=1"
            $null =  $sqlCMD1.ExecuteNonQueryAsync()
            # add wait for few ms to let the previous commend to aquire the lock on the row, as we might be faster than the database. 
            # if we are faster than the database increase the SafetyWait time so lock can be aquired. 
            Start-Sleep -Milliseconds $iSafetyWaitms
            $null =  $sqlCMD2.ExecuteNonQuery()
        }
        catch {
            #rollback transactions 
            "Exception catched.."
            $_.Exception.Message.ToString()
            $iNumberOfExceptions +=1
        }
        finally {
            
            # closing connections (anyway the dead connection will be dropped, just to be on the safe side we validating and closing both.)
            if($sqlCMD1.Transaction.Connection.State -eq "open"){
                $sqlCMD1.Transaction.Connection.Close()
                Start-Sleep -Milliseconds $iSafetyWaitms
            }
            if($sqlCMD2.Transaction.Connection.State -eq "open"){
                $sqlCMD2.Transaction.Connection.Close()
                Start-Sleep -Milliseconds $iSafetyWaitms
            }
        }
}

# closing connection (this is where temp tables will be dropped by SQL engine)
$sqlConnection1.Close()
$sqlConnection2.Close()
$sqlConnection0.Close()

"Done generating {0} deadlocks" -f $iNumberOfExceptions.ToString()
if($pNumberOfDeadlocksToGenerate -gt $iNumberOfExceptions)
    {
        "Seems like number of deadlocks generated is less the requested. it might happen due to slowness on the database side. to overcome this please increase the number in iSafetyWaitms variable. it will give more time to the database to complete the step before proceeding."
    }