# Version 1.93 (+ remove Folders to avoid treshhold)
# Version 1.92 (+ RAM size to Azure)
# Version 1.91 (+ eMailOutlook)
# Version 1.9  (+ Version To Azure)

#Import TestData
$configSpo = ([xml](Get-Content -Path ".\testdata.xml")).spo
$configAzure = ([xml](Get-Content -Path ".\testdata.xml")).azure
$configEmail = ([xml](Get-Content -Path ".\testdata.xml")).email

#AZURE TABLE DATA
Import-Module AzureRM.Profile
Import-Module Azure.Storage

$partitionKey = $env:computername
$nameKey = New-AzureStorageContext $configAzure.accountname -StorageAccountKey $configAzure.accountkey
$table = Get-AzureStorageTable -Name configAzure.tablename -Context $nameKey -ErrorAction Ignore

#JSON DATA
$jsonContent = Get-Content -Raw -Path ".\testset.json"
$JsonParameters = ConvertFrom-Json -InputObject $jsonContent


function DeleteSPOlist { 
	Param(
		[string]$SiteUrl,
		[string]$targetList)

$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $configSpo.username, $(convertto-securestring $configSpo.password -asplaintext -force)
Connect-PnPOnline -Url $SiteUrl -Credential $cred

	if ($SiteUrl = $configSpo.siteurl){
		Write-host "CLEARING TARGET ..."
			for($i = 1; $i -le 4; $i++){
				$FolderName = "20000Files-10GB-0" + $i
				Remove-PnPFolder -Name $FolderName -Folder $targetList -Force
			}
	}
	
Remove-PnPList -Identity $targetList -Force -Confirm:$false
Write-host "SPOlist deleted"
}


function ConfigRefresh { 
	Param(
		[string]$Workspace,
		[string]$Uid)

$pathConfig1 = "$env:userprofile\"+$Workspace+"\.metadata\hmigration\"+$Uid
$pathConfig2 = "$env:userprofile\"+$Workspace+"\.metadata\hmigration\configurations\"+$Uid+".xml"

Remove-Item -path $pathConfig1 -recurse -Force
Remove-Item -path $pathConfig2 -Force
Write-host "Config deleted"

$sourceObject = ".\configs\" + $Uid + ".xml"
$targetObject = "$env:userprofile\" + $Workspace + "\.metadata\hmigration\configurations\" + $Uid + ".xml"

Copy-Item -Path $sourceObject -Destination $targetObject -Force
Write-host "Config copied"
}


function RunCmdJob {
	Param(
		[string]$TestName,
		[string]$AppPath,		
		[string]$Uid,
		[string]$TimeStart)
		
$FilePath = $AppPath + "/essentialscmd.exe"
$ArgumentList = "-cmd runJob -guid " + $Uid + " -clear"

Write-host "Start Migration Job - " $TimeStart
Write-host $FilePath $ArgumentList

Start-Process -FilePath $FilePath -Wait -ArgumentList $ArgumentList
}


function WriteToAzure ($TestName, $DateStart, $AppPath) {

	#Get current App version
	$filepath = Get-ChildItem ($AppPath +"\plugins\application.navigator_*.jar")
	$Version = $filepath.BaseName -replace "application.navigator_",""
	Write-host $filepath
	Write-host "Version " $Version
	$InstalledRAM = Get-WmiObject -Class Win32_ComputerSystem
	$PcRam = [Math]::Round(($InstalledRAM.TotalPhysicalMemory/ 1GB),0)
	Write-host "InstalledRAM GB = " $PcRam
	
	$DateFinish = Get-Date
	$rowKey = $DateFinish.ToString("yyyyMMddHHmmss")
	$TimeStart = $DateStart.ToString("yyyy.MM.dd HH:mm:ss")
	$TimeFinish = $DateFinish.ToString("yyyy.MM.dd HH:mm:ss")
	$TimeSpan = New-TimeSpan -Start $TimeStart -End $TimeFinish
	[string] $TimeDif = $TimeSpan
	[string] $TimeDifMin = ([Math]::Round($TimeSpan.TotalMinutes, 2))
	
	$values = @{"TestName" = $TestName; "RAM" = $PcRam; "Version" = $Version; "TimeStart" = $TimeStart; "TimeFinish" = $TimeFinish; "Duration" = $TimeDif; "DurationMin" = $TimeDifMin}
	$entity = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity $partitionKey, $rowKey

	foreach($value in $values.GetEnumerator()) {
		$entity.Properties.Add($value.Key, $value.Value);
	}
	
	$result = $table.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity))
	
	$CsvData = $TestName + "," + $TimeStart + "," + $TimeFinish + "," + $TimeDif + "," + $TimeDifMin 
	Add-Content -Path .\timelog.csv -Value $CsvData
	Write-host "Migration Job Finished - " $TimeFinish
	Write-host "Migration Duration - " $TimeDif " (" $TimeDifMin ")"
}

function eMailOutlook ($MailTo) {
$MailCred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $configEmail.username, $(convertto-securestring $configEmail.password -asplaintext -force)
$CsvFile = ".\timelog.csv" 		
$Body = Get-Content $CsvFile | Out-String

	$mailParams = @{
		SmtpServer                 = 'smtp.office365.com'
		Port                       = '587'
		UseSSL                     = $true
		Credential                 = $MailCred
		From                       = $configEmail.mailfrom
		To                         = $MailTo
		Subject                    = "Perfomance Test Result"
		Body                       = $Body
		BodyAsHtml 				   = $true 
		Attachments				   = $CsvFile
		DeliveryNotificationOption = 'OnFailure', 'OnSuccess'
	}
Send-MailMessage @mailParams
}
	

function RunTest { 
	Param(
		[string]$TestName)

	foreach ($test in $JsonParameters.Tests){
		if ($test.TestName -eq $TestName){
			Write-host "TestName - " $TestName
			DeleteSPOlist -SiteUrl $test.TargetSite -targetList $test.TargetList
			ConfigRefresh -Workspace $test.Workspace -Uid $test.Uid
			
			$DateStart = Get-Date
			RunCmdJob -TestName $TestName -AppPath $test.AppPath -Uid $test.Uid -TimeStart $DateStart
			WriteToAzure -TestName $TestName -DateStart $DateStart -AppPath $test.AppPath
		}
	}
}


#MAIN EXECUTION

$TestRoundNum=1   #Number of Rounds
$PauseBetweenTestRounds = 600 #

for($i = 1; $i -le $TestRoundNum; $i++){
Write-host "ROUND " $i " OF " $TestRoundNum

RunTest -TestName "PerfomanceTest_DEV"
RunTest -TestName "PerfomanceTestDrops_DEV"
RunTest -TestName "PerfomanceTestRocks_DEV"

RunTest -TestName "PerfomanceTest_2.6"
RunTest -TestName "PerfomanceTestDrops_2.6"
RunTest -TestName "PerfomanceTestRocks_2.6"

Write-host "Waiting for " $PauseBetweenTestRounds " seconds to Azure complete actions for next test series"
Start-Sleep -s $PauseBetweenTestRounds
}

eMailOutlook -MailTo $configEmail.mailto
Write-host "DONE"
Start-Sleep -s 3
	
	
	
	
	