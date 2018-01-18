<#
.SYNOPSIS
    Patches the model.xml and origin.xml in a .bacpac with the master key information removed.
.DESCRIPTION
    When exporting a .bacpac from Azure SQLDB with auditing enabled, the .bacpac will contain a master key without a password in the model.xml.  A 
    master key without a password is an Azure SQLDB only feature, so it's presence prevents being able to import the .bacpac into an on-premise
    SQL Server database.  This script works around this limitation by extracting the model.xml and origin.xml from the .bacpac, removing the references
    to the master key, and then updating the .bacpac with the new model.xml and origin.xml.  The resulting .bacpac can then be imported to an on-premise 
    database.  By default, a copy of the original .bacpac is made, and the copy is updated.  Using the -skipCopy parameter will skip the copy step.
.EXAMPLE 
    C:\PS> .\RemoveMasterKey.ps1  -bacpacPath "C:\BacPacs\Test.bacpac" -skipCopy
.PARAMETER bacpacPath
    Specifies the path the .bacpac to patch.
.PARAMETER skipCopy
    If specified, copies the .bacpac before making updates.
#>
param(
    [Parameter(Mandatory=$true, HelpMessage="Specifies the path the .bacpac to patch.")]  
    [string]$bacpacPath,
    [Parameter(Mandatory=$false, HelpMessage="If specified, copies the .bacpac before making updates.")]  
    [switch]$skipCopy 
)


if ($PSVersionTable.PSVersion.Major -lt 4)
{
    Write-Host "Unsupported powershell version.  This script requires powershell version 4.0 or later"
    return
}


Add-Type -Assembly System.IO.Compression.FileSystem


$targetBacpacPath = [System.IO.Path]::GetFullPath($bacpacPath)
if (!$skipCopy)
{    
    $targetBacpacPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($targetBacpacPath),
        [System.IO.Path]::GetFileNameWithoutExtension($targetBacpacPath) + "-patched" + [System.IO.Path]::GetExtension($targetBacpacPath))
    
    Copy-Item $bacpacPath $targetBacpacPath
}


$originXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "Origin.xml")
$modelXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "model.xml")


#
# Extract the model.xml and Origin.xml from the .bacpac
#
$zip = [IO.Compression.ZipFile]::OpenRead($targetBacpacPath)
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "model.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $modelXmlFile, $true)
        break
    }
}   
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "Origin.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $originXmlFile, $true)
        break
    }
}   
$zip.Dispose()


if(![System.IO.File]::Exists($modelXmlFile)) {
    Write-Host "Could not extract the model.xml from file " + $targetBacpacPath
    return
}
if(![System.IO.File]::Exists($originXmlFile)) {
    Write-Host "Could not extract the Origin.xml from file " + $targetBacpacPath
    return
}


#
# Modify the model.xml
#
[xml]$modelXml = Get-Content $modelXmlFile
$ns = New-Object System.Xml.XmlNamespaceManager($modelXml.NameTable)
$ns.AddNamespace("x", $modelXml.DocumentElement.NamespaceURI)


$masterKeyNodes = $modelXml.SelectNodes("//x:DataSchemaModel/x:Model/x:Element[@Type='SqlMasterKey']", $ns) 
foreach ($masterKeyNode in $masterKeyNodes) {
    $masterKeyNode.ParentNode.RemoveChild($masterKeyNode)
}


$sqlDatabaseCredentialNodes = $modelXml.SelectNodes("//x:DataSchemaModel/x:Model/x:Element[@Type='SqlDatabaseCredential']", $ns) 
foreach ($sqlDatabaseCredentialNode in $sqlDatabaseCredentialNodes) {
    if ($sqlDatabaseCredentialNode.Property.Name -eq "Identity" -and $sqlDatabaseCredentialNode.Property.Value -eq "SHARED ACCESS SIGNATURE")
    {
        $sqlDatabaseCredentialNode.ParentNode.RemoveChild($sqlDatabaseCredentialNode)    
    }
}


$modelXml.Save($modelXmlFile)


#
# Modify the Origin.xml
#
[xml]$originXml = Get-Content $originXmlFile
$ns = New-Object System.Xml.XmlNamespaceManager($originXml.NameTable)
$ns.AddNamespace("x", $originXml.DocumentElement.NamespaceURI)


$databaseCredentialNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Server/x:ObjectCounts/x:DatabaseCredential", $ns) 
if ($databaseCredentialNode) {
    if ($databaseCredentialNode.InnerText -eq "1") {
        $databaseCredentialNode.ParentNode.RemoveChild($databaseCredentialNode)
    } else {
        $databaseCredentialNode.InnerText = $databaseCredentialNode.Value - 1
    }
}


$masterKeyNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Server/x:ObjectCounts/x:MasterKey", $ns) 
if ($masterKeyNode) {
    $masterKeyNode.ParentNode.RemoveChild($masterKeyNode)
}


$modelXmlHash = (Get-FileHash $modelXmlFile -Algorithm SHA256).Hash
$checksumNode = $originXml.SelectSingleNode("//x:DacOrigin/x:Checksums/x:Checksum", $ns) 
if ($checksumNode) {
    $checksumNode.InnerText = $modelXmlHash
}


$originXml.Save($originXmlFile)


#
# Update the model.xml and Origin.xml in the .bacpac
#
$zip = [System.IO.Compression.ZipFile]::Open($targetBacpacPath, "Update")
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "Origin.xml", $True) -eq 0) {
        $entryName = $entry.FullName
        $entry.Delete()
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $originXmlFile, $entryName)
        break
    }
}
foreach ($entry in $zip.Entries) {
    if ([string]::Compare($entry.Name, "model.xml", $True) -eq 0) {
        $entryName = $entry.FullName
        $entry.Delete()
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $modelXmlFile, $entryName)
        break
    }
}
$zip.Dispose()


[System.IO.File]::Delete($modelXmlFile)
[System.IO.File]::Delete($originXmlFile)


Write-Host "Completed update to the model.xml and Origin.xml in file "([System.IO.Path]::GetFullPath($targetBacpacPath))