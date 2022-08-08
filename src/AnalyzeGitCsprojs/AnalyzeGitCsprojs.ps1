
if(!$env:INETROOT) { throw 'INETROOT env variable undefined. Run this script in powershell started from enlistment.' }

$result = Get-ChildItem -Path "$env:INETROOT\private" -Filter *.csproj -Recurse | %{ 
  try { [xml]$content = Get-Content -Raw -LiteralPath $_.FullName; } catch { write-warning "invalid parse of $($_.FullName)" } 
  $rawXmlContent = $content.OuterXml; 
  $isSDK=$false; 
  if($content.Project.Sdk) { $isSDK=$true; } 
  $frameworkVersion = $content.Project.PropertyGroup.TargetFramework | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; 
  if(!$frameworkVersion) { $frameworkVersion = $content.Project.PropertyGroup.TargetFrameworkVersion | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; } 
  if(!$frameworkVersion) { $frameworkVersion = $content.Project.PropertyGroup.TargetFrameworks | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; } 
  if(!$frameworkVersion) {
    $fetchFromRedirectProps = $false;
    if($rawXmlContent -like '*xunit.qtest.props*') { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent -like '*netcore.runtime.props*') { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent -like '*xunit.cloudtest.props*') { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent -like '*azure.functions.props*') { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent -like '*netcore.props*') { $fetchFromRedirectProps=$true; }
    if($fetchFromRedirectProps) {
      $redirectProps = "$env:INETROOT\private\vNEXT\devops\build\netcore.props";
      [xml]$content = Get-Content -Raw -LiteralPath $redirectProps;
      $frameworkVersion = $content.Project.PropertyGroup.TargetFramework | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; 
    }
  }
  $isTest = $false; 
  $testType = $null;
  if($rawXmlContent -like '*mstest*' -or $rawXmlContent -like '*xunit.cloudtest.props*' -or $rawXmlContent -like '*xunit.qtest.props*') {
    $isTest=$true;
    if($rawXmlContent -like '*MSTestV2.props*') { $testType='MSTestV2.props'; }
    elseif($rawXmlContent -like '*MSTestV2Import.props*') { $testType='MSTestV2Import.props'; }
    elseif($rawXmlContent -like '*MSTest2010.props*') { $testType='MSTest2010.props'; }
    elseif($rawXmlContent -like '*MSTest2012.props*') { $testType='MSTest2012.props'; }
    elseif($rawXmlContent -like '*xunit.cloudtest.props*') { $testType='xunit.cloudtest.props'; }
    elseif($rawXmlContent -like '*xunit.qtest.props*') { $testType='xunit.qtest.props'; }
    elseif($rawXmlContent -like '*Microsoft.NET.Test.Sdk*') { $testType='PackageRef1'; }
    elseif($rawXmlContent -like '*MSTest.TestAdapter*') { $testType='PackageRef2'; }
    elseif($rawXmlContent -like '*MSTest.TestFramework*') { $testType='PackageRef3'; }
    elseif($rawXmlContent -like '*MSTest2010.Library.1.0.3690908-legacy-001-1*') { $testType='MSTest2010Legacy'; }
    elseif($rawXmlContent -like '*MSTest2012.Library.1.0.3625316-legacy-001-1*') { $testType='MSTest2012Legacy'; }
    elseif($rawXmlContent -like '*packages\Mstest2010.Library*') { $testType='MSTest2010Legacy_2'; }
  }
  return New-Object PSObject -Property @{ 
    FullPath=$($_.FullName.Replace($env:INETROOT,'').Trim('/').Trim('\')); 
    isSDK=$isSDK; 
    frameworkVersion=$frameworkVersion;
    isTest=$isTest;
    testType=$testType;
  };
}
