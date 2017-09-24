Login-AzureRmAccount

$arrayTableFound = @()

foreach($sub in Get-AzureRmSubscription)
{
    Write-Host 'Looking for table auditing in subscription'$sub.Name'('$sub.SubscriptionId')'

    Set-AzureRmContext -SubscriptionName $sub.Name
    $sqlServers = Get-AzureRmResourceGroup | Get-AzureRmSqlServer
    foreach($sqlServer in $sqlServers)
    {       
		$serverName = $sqlServer.ServerName
		Write-Host 'Looking for table auditing on server'$serverName

		$serverAuditingPolicy = $sqlServer | Get-AzureRmSqlServerAuditingPolicy -WarningAction SilentlyContinue 
		
		if ($serverAuditingPolicy.AuditState -eq 'Enabled' -and $serverAuditingPolicy.AuditType -eq 'Table')
		{
			Write-Host -ForegroundColor Red 'Found table auditing on server'$serverName                
			$arrayTableFound += ,@("SERVER: $serverName")
		}
		foreach($sqlDB in $sqlServer | Get-AzureRmSqlDatabase)
		{

			if ($sqlDB.DatabaseName -eq 'master')
			{
				#no support for auditing on master
				continue
			}
			Write-Host 'Looking for table auditing on DB'$sqlDB.DatabaseName
			$DBAuditingPolicy = Get-AzureRmSqlDatabaseAuditingPolicy -ServerName $sqlServer.ServerName -DatabaseName $sqlDB.DatabaseName -ResourceGroupName $sqlDB.ResourceGroupName -WarningAction SilentlyContinue 
		
			if ($DBAuditingPolicy.AuditState -eq 'Enabled' -and $DBAuditingPolicy.AuditType -eq 'Table')
			{
				Write-Host -ForegroundColor Red 'Found table auditing on database'$sqlDB.DatabaseName'Server'$sqlServer.ServerName
				$databaseName = $sqlDB.DatabaseName              
				$arrayTableFound += ,@("DATABASE: $databaseName (on Server $serverName)")
			}
		}
    }
}

Write-Host -ForegroundColor Green 'Total resources with Table auditing:'$arrayTableFound.Length

Write-Host -ForegroundColor Red 'The following resources have Table auditing enabled:'

foreach($item in $arrayTableFound)
{
    Write-Host -ForegroundColor Red $item[0]
} 
