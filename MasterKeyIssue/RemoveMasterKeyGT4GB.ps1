<#
.SYNOPSIS
    Given a new [file].bacpac, creates a new [file]-patched.bacpac with master key information removed from the model.xml and origin.xml.
.DESCRIPTION
    When exporting a .bacpac from Azure SQLDB with auditing enabled, the .bacpac will contain a master key without a password in the model.xml.  A 
    master key without a password is an Azure SQLDB only feature, so it's presence prevents being able to import the .bacpac into an on-premise
    SQL Server database.  This script works around this limitation by extracting the model.xml and origin.xml from the .bacpac, removing the references
    to the master key, and creating a new .bacpac with the updated model.xml and origin.xml.  The resulting .bacpac can then be imported to an on-premise 
    database.
.EXAMPLE 
    C:\PS> .\RemoveMasterKey.ps1 -bacpacPath "C:\BacPacs\Test.bacpac"   # Generates a Test-patched.bacpac file
.PARAMETER bacpacPath
    Specifies the path the .bacpac to patch.
#>
param(
    [Parameter(Mandatory=$true, HelpMessage="Specifies the path the .bacpac.  This file will not be modified.")]  
    [string]$bacpacPath
)


if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Host "Unsupported powershell version.  This script requires powershell version 4.0 or later"
    return
}


Add-Type -Assembly System.IO.Compression.FileSystem


$targetBacpacPath = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($bacpacPath),
    [System.IO.Path]::GetFileNameWithoutExtension($bacpacPath) + "-patched" + [System.IO.Path]::GetExtension($bacpacPath))
$originXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "Origin.xml")
$modelXmlFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($targetBacpacPath), "model.xml")


if ([System.IO.File]::Exists($targetBacpacPath)) {
    [System.IO.File]::Delete($targetBacpacPath)
}


#
# Extract the model.xml and Origin.xml from the .bacpac
#
$zip = [System.IO.Compression.ZipFile]::OpenRead($bacpacPath)
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
    Write-Host "Could not extract the model.xml from file " + $bacpacPath
    return
}
if(![System.IO.File]::Exists($originXmlFile)) {
    Write-Host "Could not extract the Origin.xml from file " + $bacpacPath
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
# Create the new .bacpac using the patched model.xml and Origin.xml
#
$zipSource = [System.IO.Compression.ZipFile]::OpenRead($bacpacPath)
$zipTarget = [System.IO.Compression.ZipFile]::Open($targetBacpacPath, "Create")
foreach ($entry in $zipSource.Entries) {
    if ([string]::Compare($entry.Name, "Origin.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipTarget, $originXmlFile, $entry.FullName)
    } elseif ([string]::Compare($entry.Name, "model.xml", $True) -eq 0) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipTarget, $modelXmlFile, $entry.FullName)
    } else {
        $targetEntry = $zipTarget.CreateEntry($entry.FullName)
        $sourceStream = $null
        $targetStream = $null        
        try {
            $sourceStream = [System.IO.Stream]$entry.Open()
            $targetStream = [System.IO.Stream]$targetEntry.Open()        
            $sourceStream.CopyTo($targetStream)
        }
        finally {
            if ($targetStream -ne $null) {
                $targetStream.Dispose()
            }
            if ($sourceStream -ne $null) {
                $sourceStream.Dispose()
            }
        }
    }
}
$zipSource.Dispose()
$zipTarget.Dispose()


[System.IO.File]::Delete($modelXmlFile)
[System.IO.File]::Delete($originXmlFile)


Write-Host "Completed update to the model.xml and Origin.xml in file"([System.IO.Path]::GetFullPath($targetBacpacPath))