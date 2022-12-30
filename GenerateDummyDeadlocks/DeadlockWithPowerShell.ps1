$pServer = '{Azure SQL Server as FQDN}'
$pDatabase = '{DatabaseName}'
$pLoginName = '{LoginName}'
$pPassword = '{Password}'
$pNumberOfDeadlocksToGenerate = 10

"Using:"
"   Server Name: " + $pServer
"   Database Name: " +$pDatabase
"   Login Name: " +$pLoginName
"   Password: ******"

$iTableName = '##dltab'
$iSQLPreperation = `
'
create table ['+ $iTableName +'1] (i int); 
create table ['+ $iTableName +'2] (i int); 
insert into ['+$iTableName+'1] values(0);
insert into ['+$iTableName+'2] values(0);

' 

$iSQLSessionA = `
'
begin transaction
update ['+$iTableName+'1] set i=1
waitfor delay ''00:00:02''
update ['+$iTableName+'2] set i=1
commit
'

$iSQLSessionB = `
'
begin transaction
update ['+$iTableName+'2] set i=2
waitfor delay ''00:00:02''
update ['+$iTableName+'1] set i=1
commit
'


# Preperation
"Running table preperation command..."
Invoke-Sqlcmd -ServerInstance $pServer -Database $pDatabase -Username $pLoginName -Password $pPassword -Query $iSQLPreperation

"Starting deadlock loop..."
for($i=1; $i -le $pNumberOfDeadlocksToGenerate; $i++)
    {
    # Session A
    $jobA = Start-Job -ScriptBlock {
        Invoke-Sqlcmd -ServerInstance $using:pServer -Database $using:pDatabase -Username $using:pLoginName -Password $using:pPassword -Query $using:iSQLSessionA
        }   

    Start-Sleep -Seconds 1

    # Session B
    $jobB = Start-Job -ScriptBlock {
        Invoke-Sqlcmd -ServerInstance $using:pServer -Database $using:pDatabase -Username $using:pLoginName -Password $using:pPassword -Query $using:iSQLSessionB
        }
    
    # Wait until finish
    Get-Job | Wait-Job | Out-Null

    # Write output
    $jobA | Receive-Job
    $jobB | Receive-Job

    # Notify user about the progress
    (get-date).DateTime.ToString() + " | " + $i.ToString() + " Deadlock completed."
    }

"Done."




