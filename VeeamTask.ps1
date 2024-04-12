param([Parameter(Position=0,mandatory=$True)][string]$SourcePath,
[Parameter(Position=1,mandatory=$True)][string]$DestinationPath,
[Parameter(Position=2,mandatory=$False)][string]$LogFile="$home/Logs/$($myinvocation.mycommand.name.Replace(".ps1","Log.$((get-date).ToShortDateString().Replace(".","-"))-$((get-date).ToShortTimeString().Replace(":","-")).log"))"
)



	function Log()
	{
		param(
		[string]$log
		)
		$message = "$((get-date -Format "dd.MM.yyyy HH:mm:ss"))`t$($log -Replace "`n",' ')"
		Tee-Object -InputObject "$message" -FilePath "$logFile" -Append
	}

	function GetItemType()
	{
		param(
		$item
		)
		if($item -isnot [System.IO.FileSystemInfo])
		{
			$item = (get-item -force $item)
		}
		if( $item -is [System.IO.DirectoryInfo])
		{
			return "Directory"
			
		}
		else
		{
			return "File"
			
		}
	}


	function CheckItemExistence()
	{
		param(
		[string]$path
		)	
		
		return (Test-Path -Path $path)
		
	}





	function EnsureDirectories()
	{
		param(
		[string]$sPath,
		[string]$destPath,
		[string]$logPath
		)
		
		if( -not (CheckItemExistence $sPath) )
		{
			Log "The source path $sPath does not exist."
			exit;
			
		}
		if( -not (CheckItemExistence $destPath) )
		{
			Log "The destination path $destPath does not exist."
			$destDir=New-item -type Directory -path $destpath
			Log "The destination path $($destDir.fullname) created."
		}
		if( -not (CheckItemExistence $logDirPath) )
		{
			Log "The log path $logPath does not exist."
			$logDir=New-item -type Directory -path $logPath
			Log "The log path $($logDir.fullname) created."
		}
	}

	function CreateDirectory()
	{
		param(
		[string]$Path
		)
		
		$dir = new-item -type Directory -path $Path
		Log "Creating directory $($dir.Fullname)"
		
	}
	function RemoveDirectory()
	{
		param(
		$Path
		)
		
		get-childitem -literalpath $Path -force| ForEach-Object{
			if((GetItemType $_) -eq "Directory")
			{
				#write-host "RECURSE Dir removal of $($_.fullname)" -fore red
				RemoveDirectory $_.Fullname
			}
			else
			{
				#write-host "RECURSE Fil removal of $($_.fullname)" -fore red
				RemoveFile $_.Fullname
			}
			
		}
		$removedItemName = (get-item -literalpath $Path).Fullname
		remove-item -literalpath $removedItemName -force #-verbose
		Log "Removing directory $removedItemName"
		
		
	}
	function CopyFile()
	{
		param(
		$sPath,
		$dPath
		)
		$destitemPathParentDir = Split-Path $dPath
		if (-not (CheckItemExistence $destitemPathParentDir))
		{
			CreateDirectory $destitemPathParentDir
		
		}
		copy-item -literalpath $sPath -destination $dPath #-verbose #-force
		Log "Copying file $(resolve-path $sPath) -> $(resolve-path $dPath)"
			
	}

	function RemoveFile()
	{
		param(
		$Path
		)
		
		$removedItemName = (get-item -literalpath $Path).Fullname
		remove-item -literalpath $removedItemName -force #-verbose
		Log "Removing file $removedItemName"
		
	}


	$logDirPath = split-path $logFile

	EnsureDirectories $SourcePath $DestinationPath $LogDirPath
	$SourcePath = (Resolve-Path $SourcePath).Path.Trim("/\")
	$DestinationPath = (Resolve-Path $DestinationPath).Path.Trim("/\")


	$allFiles=New-Object System.Collections.Generic.HashSet[string]
	$originalFiles=@{};
	$originalFiles[$SourcePath]=get-item -force $SourcePath
	Get-ChildItem $SourcePath -recurse -force| ForEach-Object{$originalFiles[$_.fullname]=$_;$item=$_.Fullname.Substring($SourcePath.Length);$allFiles.Add($item)|out-null }
	Log "Loaded $SourcePath :`n$(@($originalFiles.GetEnumerator()|Where-Object{$_.Value -isnot [System.IO.DirectoryInfo]}).Count) files`n$(@($originalFiles.GetEnumerator()|Where-Object{$_.Value -is [System.IO.DirectoryInfo]}).Count) directories"
	$replicaFiles=@{};
	$replicaFiles[$DestinationPath]=get-item -force $DestinationPath
	Get-ChildItem $DestinationPath -recurse -force| ForEach-Object{$replicaFiles[$_.fullname]=$_;$item = $_.Fullname.Substring($DestinationPath.Length);$allFiles.Add($item)|out-null }
	Log "Loaded $DestinationPath with $(@($replicaFiles.GetEnumerator()|Where-Object{$_.Value -isnot [System.IO.DirectoryInfo]}).Count) files and $(@($replicaFiles.GetEnumerator()|Where-Object{$_.Value -is [System.IO.DirectoryInfo]}).Count) directories"

foreach($itempath in ($allFiles|Sort-Object))
{
	
	$sourceitemPath = Join-path -Path $SourcePath -ChildPath $itemPath
	$destitemPath = Join-path -Path $DestinationPath -ChildPath $itemPath
	#write-host "Evaluating $itemPath" -fore red

	#item present in original,missing in replicaFiles
	if( $originalFiles.ContainsKey($sourceitemPath)   -and -not $replicaFiles.ContainsKey($destitemPath) )
	{
		#item is directory
		if( (GetItemType $sourceitemPath) -eq "Directory")
		{
			CreateDirectory $destitemPath
			
		}
		#item is file
		else
		{
			CopyFile $sourceitemPath $destitemPath
		}
		
		
		
	}
	#item missing in original, present in replicaFiles
	elseif( -not $originalFiles.ContainsKey($sourceitemPath)  -and $replicaFiles.ContainsKey($destitemPath) )
	{
		$destitemPathParentDir = Split-Path $destitemPath
		#write-host "$destitemPath has parent $destitemPathParentDir - present?  $($replicaFiles.ContainsKey($destitemPathParentDir)) $($replicaFiles.Count)" -fore cyan
		
			if($replicaFiles.ContainsKey($destitemPathParentDir))
			{
				#item is directory
				if( (GetItemType $replicaFiles[$destitemPath]) -eq "Directory")
				{
					RemoveDirectory $destitemPath;
				}
				#item is file
				else
				{
					RemoveFile $destitemPath
								
				}
			}
		
		#write-host "REMOVING FROM LIST $destitemPath : $($replicaFiles[$destitemPath])" -fore cyan
		$replicaFiles.remove($destitemPath)
		
	}
	#item present in both
	elseif(  $originalFiles.ContainsKey($sourceitemPath)  -and $replicaFiles.ContainsKey($destitemPath) )
	{
		

		#original is file,replica is directory
		if( (GetItemType $originalFiles[$sourceitemPath]) -ne "Directory" -and (GetItemType $replicaFiles[$destitemPath]) -eq "Directory" )
		{
			RemoveDirectory $destitemPath
			CopyFile $sourceitemPath $destitemPath
		}
		#original is file,replica is file
		elseif( (GetItemType $originalFiles[$sourceitemPath]) -ne "Directory" -and (GetItemType $replicaFiles[$destitemPath]) -ne "Directory" )
		{
			CopyFile $sourceitemPath $destitemPath
		}
		#original is directory,replica is file
		elseif( (GetItemType $originalFiles[$sourceitemPath]) -eq "Directory" -and (GetItemType $replicaFiles[$destitemPath]) -ne "Directory" )
		{
			RemoveFile $destitemPath
			CreateDirectory $destitemPath
		}
		#if both are directories and already present,no action needed
		
		
	}
	
	
	
}

write-host "Log file = $logFile"

