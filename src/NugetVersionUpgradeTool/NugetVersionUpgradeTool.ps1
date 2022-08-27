
############ NuGet Helpers #############

function _ToPackageObject($packageId, $packageVersion, [int]$depth=0) {
  return New-Object "System.Tuple[string,string,int]" -ArgumentList $packageId,$packageVersion,$depth;
}

function _ComparePackageVersion($versionStr1, $versionStr2) {
  $versionSplit1 = $versionStr1 -split '\.';
  $versionArr1 = @(0,1,2) | %{ if($_ -lt $versionSplit1.Length) { $versionSplit1[$_] } else { '0' } };
  $versionSplit2 = $versionStr2 -split '\.';
  $versionArr2 = @(0,1,2) | %{ if($_ -lt $versionSplit2.Length) { $versionSplit2[$_] } else { '0' } };
  $index=0;
  while($index -lt 3 -and $versionArr1.Length -gt $index -and $versionArr2.Length -gt $index) {
    [int]$versionInt1 = -1;
    [int]$versionInt2 = -1;
    if([int]::TryParse($versionArr1[$index], [ref]$versionInt1) -and [int]::TryParse($versionArr2[$index], [ref]$versionInt2)) {
      $result = $versionInt1-$versionInt2;
      if($result -ne 0) {
        return $result;
      }
    } else {
      $result = [string]::Compare($versionArr1[$index], $versionArr2[$index], [System.StringComparison]::Ordinal);
      if($result -ne 0) {
        return $result;
      }
    }
    $index++;
  }
  return 0;
}

function _GetPackageDependencies ($packageId, $packageVersion, $depth, [string]$NugetRepository) {
  if(!$packageId -or !$packageVersion) {
    Write-Error "GetPackageDependencies: invalid input - empty packageId $packageId or packageVersion $packageVersion";
    return;
  }
  $SavedProgressPreference = $ProgressPreference; 
  $ProgressPreference = 'SilentlyContinue'; 
  try
  {
    if($NugetRepository) {
        $package = (Find-Module -Name $packageId -RequiredVersion $packageVersion -Repository $NugetRepository -ErrorAction Stop);
    } else {
        $package = (Find-Module -Name $packageId -RequiredVersion $packageVersion -ErrorAction Stop);
    }
    $package.Dependencies | %{ _ToPackageObject $_.Name $_.MinimumVersion $depth; } ;
  } catch {
    Write-Warning "GetPackageDependencies: $($_.Exception). Requested PackageId=$packageId PackageVersion=$packageVersion.";
    Write-Warning "Make sure you install all dependencies - e.g., Install-Module PackageManagement -Force; Install-Module PowerShellGet -Force; Register-PsRepository 'BingAdsPackages' -SourceLocation 'https://pkgs.dev.azure.com/msasg/_packaging/BingAdsPackages/nuget/v2';";
  } finally {
    $ProgressPreference = $SavedProgressPreference;
  }
}

$global:ENABLE_PARALLEL_DOWNLOAD_TRANSITIVEDEPENDENCIES = $false;

function _GetTransitiveDependencies ([string[]]$packageIdVersionPairs, [string]$NugetRepository, [bool]$verboseLogging = $true) {
  _LogInfo "GetTransitiveDependencies: $packageIdVersionPairs" -verboseLogging $verboseLogging;

  $startTime = Get-Date;

  $queue = New-Object "System.Collections.Concurrent.ConcurrentQueue[System.Tuple[string,string,int]]";
  $parsedPackages = [hashtable]::Synchronized(@{ });

  $packageIdVersionPairs | %{ 
    $packageIdVersionPair = $_ -split '/';
    $queue.Enqueue((_ToPackageObject $packageIdVersionPair[0] $packageIdVersionPair[1] 0));
  };

  if(!($global:ENABLE_PARALLEL_DOWNLOAD_TRANSITIVEDEPENDENCIES -and (get-host).Version.Major -ge 7)) {
    $item = New-Object "System.Tuple[string,string,int]" -ArgumentList "invalid","invalid",9999999;
    while($queue.Count -gt 0) {
      if($queue.TryDequeue([ref]$item)) {
        _ProcessQueueItemForTransitiveDependencies $item.Item1 $item.Item2 $item.Item3 $queue $parsedPackages $NugetRepository $verboseLogging;
      }
    }
  } else { ### this logic is too complex and may not work.
    _ProcessQueueItemForTransitiveDependenciesAsync $item.Item1 $item.Item2 $item.Item3 $queue $parsedPackages $NugetRepository $verboseLogging;
  }

  _LogInfo "GetTransitiveDependencies: elapsed=$(((Get-Date)-$startTime).TotalSeconds)s" -verboseLogging $verboseLogging;
  return [hashtable]$parsedPackages;
}

function _ProcessQueueItemForTransitiveDependenciesAsync( ### this logic is too complex and may not work.
  [string]$packageId, [string]$packageVersion, [int]$depth, $queueInput, [hashtable]$parsedPackages, [string]$NugetRepository, [bool]$verboseLogging, [int]$threadId=-1) 
{
  ### this logic is too complex and may not work.
  # this is needed because existing functions are inaccessible in -Parallel
  $funcDef__ProcessQueueItemForTransitiveDependencies = $function:_ProcessQueueItemForTransitiveDependencies.ToString();
  $funcDef__GetPackageDependencies = $function:_GetPackageDependencies.ToString();
  $funcDef__LogInfo = $function:_LogInfo.ToString();
  $funcDef__ToPackageObject = $function:_ToPackageObject.ToString();
  $funcDef__ComparePackageVersion = $function:_ComparePackageVersion.ToString();
  $threadProcessing = [hashtable]::Synchronized(@{ });
  $DownloadThrottleLimit = 10;
  0..($DownloadThrottleLimit-1) | ForEach-Object -ThrottleLimit $DownloadThrottleLimit -Parallel {
    # this is needed because existing functions are inaccessible in -Parallel
    $function:_ProcessQueueItemForTransitiveDependencies = $using:funcDef__ProcessQueueItemForTransitiveDependencies;
    $function:_GetPackageDependencies = $using:funcDef__GetPackageDependencies;
    $function:_LogInfo = $using:funcDef__LogInfo;
    $function:_ToPackageObject = $using:funcDef__ToPackageObject;
    $function:_ComparePackageVersion = $using:funcDef__ComparePackageVersion;
    $queue = $using:queueInput;
    $threadProcessing = $using:threadProcessing;
    $threadId = $_;
    $item = New-Object "System.Tuple[string,string,int]" -ArgumentList "invalid","invalid",9999999;
    while($true) {
      if($queue.Count -eq 0) {
        sleep -Milliseconds 100;
        if(($threadProcessing.Keys | where { $threadProcessing[$_] } | select -First 1 | measure).Count -eq 0) {
          break;
        }
        continue;
      }
      $threadProcessing[$threadId]=$true;
      try {
        if($queue.TryDequeue([ref]$item)) {
          _ProcessQueueItemForTransitiveDependencies $item.Item1 $item.Item2 $item.Item3 $queue $using:parsedPackages $using:NugetRepository $using:verboseLogging $threadId;
        }
      } finally {
        $threadProcessing[$threadId]=$false;
      }
    }
  }
}

function _ProcessQueueItemForTransitiveDependencies([string]$packageId, [string]$packageVersion, [int]$depth, $queue, [hashtable]$parsedPackages, [string]$NugetRepository, [bool]$verboseLogging, [int]$threadId=-1) {
  if(!$parsedPackages.ContainsKey($packageId)) {
    _LogInfo "parse   : [$packageId, $packageVersion]" -verboseLogging $verboseLogging -threadId $threadId; 
    $dependencies = (_GetPackageDependencies $packageId $packageVersion ($depth+1) -NugetRepository $NugetRepository);
    $dependencies | %{ $queue.Enqueue($_); }
    $parsedPackages[$packageId] = $packageVersion;
  } else {
    $compareResult = (_ComparePackageVersion $packageVersion $parsedPackages[$packageId]);
    if($compareResult -gt 0) {
      _LogInfo "update  : [$packageId, $packageVersion] <- [$($parsedPackages[$packageId])]" -verboseLogging $verboseLogging -threadId $threadId; 
      $parsedPackages[$packageId] = $packageVersion;
    } elseif ($compareResult -ne 0) {
      #_LogInfo "skip    : [$packageId, $($parsedPackages[$packageId])] xx [$packageVersion]" -verboseLogging $verboseLogging -threadId $threadId; 
    }
  }
}

function _LogInfo($message, [bool]$verboseLogging = $true, [int]$threadId = -1) {
  if($verboseLogging) {
    if($threadId -and $threadId -ne -1) {
      $message = "$message `t@thread#$threadId";
    }
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] $message"; 
  }
}

############ Enlistment Helpers #############

function _GetPackageIdsFromConfig ($path) {
  $keys = @{}; 
  [xml]$config = Get-Content $path -Raw;
  $config.Project.ItemGroup.PackageReference | where { $_.Update } | %{ $keys[$_.Update]=$_.Version; };
  return $keys;
}

function _FindUpdateReadyPackageIds ([hashtable]$keys, [hashtable]$keysMergeSrc, [bool]$verboseLogging = $true) {
  $updatedKeys = @{};
  $keys.Keys | %{ 
    $packageId = $_;
    if($keysMergeSrc.ContainsKey($packageId)) {
      $compareResult = (_ComparePackageVersion $keysMergeSrc[$packageId] $keys[$packageId]);
      if($compareResult -gt 0) {
        _LogInfo "update  : [$packageId, $($keys[$packageId])] -> [$($keysMergeSrc[$packageId])]" -verboseLogging $verboseLogging;
        $updatedKeys[$packageId] = $keysMergeSrc[$packageId];
      }
    }
  };
  return $updatedKeys;
}

function _MergeToPackageConfig ($path, [hashtable]$updates, [bool]$verboseLogging = $true) {
  _LogInfo "MergeToPackageConfig: parsing $path" -verboseLogging $verboseLogging;
  $anyUpdate = $false;

  $result = Get-Content $path | %{ 
    $matchResult = ($_ -match 'PackageReference.+Update="([a-zA-Z0-9\.]+)".+Version="([a-zA-Z0-9\-\.]+)"');
    if($matchResult -and $Matches[1] -and $Matches[2]) {
      $packageId = $Matches[1];
      $packageVersion = $Matches[2];
      if($updates.ContainsKey($packageId)) {
        $anyUpdate = $true;
        return ($_ -replace $packageVersion,$($updates[$packageId]));
      }
    }
    return $_;
  }; 
  if(!$anyUpdate) {
    _LogInfo 'MergeToPackageConfig: skip; nothing to update' -verboseLogging $verboseLogging;
    return;
  }
  _LogInfo "MergeToPackageConfig: updating $path" -verboseLogging $verboseLogging;
  Set-Content -LiteralPath $path -Value $result; 
}

function _UpgradePackageConfig([string]$path, [hashtable]$packageIdVersionHashtableToUpdate, [bool]$verboseLogging = $true) {
    $actualPackageInfo = _GetPackageIdsFromConfig -path $path;
    $deltaPackageInfo = _FindUpdateReadyPackageIds -keys $actualPackageInfo -keysMergeSrc $packageIdVersionHashtableToUpdate -verboseLogging $verboseLogging;
    _MergeToPackageConfig -path $path -updates $deltaPackageInfo -verboseLogging $verboseLogging;
}

function UpgradePackageConfig(
    ### path to global packages.props file.
    [Parameter(Mandatory=$true)][string]$Path, 
    ### packageId-Version(s) in the format of "packageId/packageVersion" e.g, @('CoreWCF.Http/1.0.2', 'CoreWCF.Primitives/1.0.2').
    [Parameter(Mandatory=$true)][string[]]$PackageIdVersionPairsToUpdate, 
    ### Nuget-Repository-Id. Create e.g., Install-Module PackageManagement -Force; Install-Module PowerShellGet -Force; Register-PsRepository 'BingAdsPackages' -SourceLocation 'https://pkgs.dev.azure.com/msasg/_packaging/BingAdsPackages/nuget/v2';
    [string]$NugetRepository = $null,
    ### enable verbose logging.
    [bool]$VerboseLogging = $true,
    ### cache for testing
    [bool]$UseGlobalNuGetDependencyCache = $false) 
{
<#
.SYNOPSIS
Upgrades global Packages.props file. 
.LINK
https://github.com/AAATechGuy/AbinzSharedTools 
#>
    if($UseGlobalNuGetDependencyCache -and $global:GLOBAL_NUGET_DEPENDENCY_CACHE) {
      [hashtable]$deps = $global:GLOBAL_NUGET_DEPENDENCY_CACHE;
    } 
    if(!$deps) {
      $deps = _GetTransitiveDependencies $packageIdVersionPairsToUpdate -verboseLogging $verboseLogging -NugetRepository $NugetRepository -ErrorAction Stop;
    }
    _UpgradePackageConfig -path $path -packageIdVersionHashtableToUpdate $deps -verboseLogging $verboseLogging -ErrorAction Stop;
    $global:GLOBAL_NUGET_DEPENDENCY_CACHE = $deps;
}
