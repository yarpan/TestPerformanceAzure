$DateStart = Get-Date
$configSpo = ([xml](Get-Content -Path ".\testdata.xml")).spo
$ListName = "List_OneMillionItems"

$cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $configSpo.username, $(convertto-securestring $configSpo.password -asplaintext -force)
Connect-PnPOnline -Url $configSpo.siteurl -Credential $cred

function GenerateItems ($A1) {

	$FolderName = "Folder_100.000_" + $A1
	$PathName = "Lists/" + $ListName
	Add-PnPFolder -Name $FolderName -Folder $PathName
	
	for($A2=0; $A2 -lt 10; $A2++){
	
		$FolderName2 = "Folder_10.000_" + $A2
		$PathName2 = "Lists/" + $ListName + "/" + $FolderName
		Add-PnPFolder -Name $FolderName2 -Folder $PathName2
		
		for($A3=0; $A3 -lt 10; $A3++){

			$FolderName3 = "Folder_1.000_" + $A3
			$PathName3 = "Lists/" + $ListName + "/" + $FolderName + "/" + $FolderName2
			Add-PnPFolder -Name $FolderName3 -Folder $PathName3
			Write-host
			Write-host (Get-Date)
			Write-host $FolderName "/" $FolderName2 "/" $FolderName3 " START" 
	
			for($A4=0; $A4 -lt 1000; $A4++){
				$ItemName= "item_" + $A1 + "_" + $A2 + "_" + $A3 + "_" + $A4
				$FolderName4 = $FolderName + "/" + $FolderName2 + "/" + $FolderName3
				$FakeItem = Add-PnPListItem -List $ListName -Values @{"Title" = $ItemName} -Folder $FolderName4
			}
		}
	}
}

GenerateItems -A1 "1"
$DateFinish = Get-Date
$TimeSpan = New-TimeSpan -Start $DateStart -End $DateFinish
Write-host
Write-host "DateStart " $DateStart " / DateFinish " $DateFinish " / Total time " $TimeSpan